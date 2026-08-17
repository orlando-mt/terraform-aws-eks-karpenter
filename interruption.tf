# ---------------------------------------------------------------------------
# Interruption handling.
#
# EC2 announces Spot reclaims, rebalance recommendations and scheduled
# maintenance through EventBridge. Karpenter consumes them from this queue and
# drains the node gracefully instead of letting workloads die with it.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  name                      = local.queue_name
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = var.interruption_queue_kms_key_id == null
  kms_master_key_id         = var.interruption_queue_kms_key_id

  tags = var.tags
}

data "aws_iam_policy_document" "interruption_queue" {
  statement {
    sid    = "AllowEventBridgeToSendMessages"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption.arn]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:*"]
    resources = [aws_sqs_queue.interruption.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  queue_url = aws_sqs_queue.interruption.id
  policy    = data.aws_iam_policy_document.interruption_queue.json
}

locals {
  interruption_events = {
    spot_interruption = {
      description = "Spot instance about to be reclaimed"
      detail_type = ["EC2 Spot Instance Interruption Warning"]
      source      = "aws.ec2"
    }
    rebalance = {
      description = "Spot rebalance recommendation"
      detail_type = ["EC2 Instance Rebalance Recommendation"]
      source      = "aws.ec2"
    }
    instance_state_change = {
      description = "Instance state change"
      detail_type = ["EC2 Instance State-change Notification"]
      source      = "aws.ec2"
    }
    scheduled_change = {
      description = "Scheduled maintenance affecting the instance"
      detail_type = ["AWS Health Event"]
      source      = "aws.health"
    }
  }
}

resource "aws_cloudwatch_event_rule" "interruption" {
  for_each = local.interruption_events

  name        = "${local.queue_name}-${each.key}"
  description = each.value.description

  event_pattern = jsonencode({
    source        = [each.value.source]
    "detail-type" = each.value.detail_type
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "interruption" {
  for_each = local.interruption_events

  rule      = aws_cloudwatch_event_rule.interruption[each.key].name
  target_id = "KarpenterInterruptionQueue"
  arn       = aws_sqs_queue.interruption.arn
}
