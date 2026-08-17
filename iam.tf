locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# Node role.
#
# Assumed by every instance Karpenter launches. Karpenter creates and manages
# the instance profiles itself, so only the role is defined here.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name        = coalesce(var.node_role_name, "${var.cluster_name}-karpenter-node")
  description = "Role for nodes launched by Karpenter on ${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(var.tags, { Name = coalesce(var.node_role_name, "${var.cluster_name}-karpenter-node") })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset(concat([
    "arn:${local.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:${local.partition}:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:${local.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ], var.enable_node_ssm ? ["arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"] : [], var.node_additional_policy_arns))

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# Nodes must be registered with the cluster to join it. With API
# authentication this is an access entry rather than an aws-auth entry.
resource "aws_eks_access_entry" "node" {
  count = var.create_node_access_entry ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.node.arn
  type          = "EC2_LINUX"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Controller role (IRSA)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "controller" {
  name        = coalesce(var.controller_role_name, "${var.cluster_name}-karpenter-controller")
  description = "IRSA role for the Karpenter controller on ${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = var.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_issuer}:sub" = "system:serviceaccount:${var.namespace}:${local.service_account_name}"
            "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "controller" {
  name = coalesce(var.controller_role_name, "${var.cluster_name}-karpenter-controller")
  role = aws_iam_role.controller.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadEC2"
        Effect = "Allow"
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        # Creating capacity is scoped to resources tagged for this cluster
        Sid      = "CreateTaggedResources"
        Effect   = "Allow"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "RunInstancesFromExistingResources"
        Effect = "Allow"
        Action = ["ec2:RunInstances"]
        Resource = [
          "arn:${local.partition}:ec2:*::image/*",
          "arn:${local.partition}:ec2:*::snapshot/*",
          "arn:${local.partition}:ec2:*:*:security-group/*",
          "arn:${local.partition}:ec2:*:*:subnet/*",
          "arn:${local.partition}:ec2:*:*:capacity-reservation/*"
        ]
      },
      {
        Sid      = "TagResourcesOnCreate"
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
            "ec2:CreateAction"                                         = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
        }
      },
      {
        # Terminating and retagging is limited to instances this cluster owns
        Sid      = "ManageOwnedResources"
        Effect   = "Allow"
        Action   = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate", "ec2:CreateTags"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          }
        }
      },
      {
        # Instance profiles are created and cleaned up by Karpenter itself
        Sid    = "ManageInstanceProfiles"
        Effect = "Allow"
        Action = [
          "iam:CreateInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceAccount" = local.account_id
          }
        }
      },
      {
        # Only the node role may be attached to the instances it launches
        Sid      = "PassNodeRole"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.node.arn
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid      = "ReadAmiParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:${local.partition}:ssm:*::parameter/aws/service/*"
      },
      {
        # Used to pick the cheapest instance type that fits a pod
        Sid      = "ReadPricing"
        Effect   = "Allow"
        Action   = ["pricing:GetProducts"]
        Resource = "*"
      },
      {
        Sid      = "ReadCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:${local.partition}:eks:*:${local.account_id}:cluster/${var.cluster_name}"
      },
      {
        Sid      = "ConsumeInterruptionQueue"
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = aws_sqs_queue.interruption.arn
      }
    ]
  })
}
