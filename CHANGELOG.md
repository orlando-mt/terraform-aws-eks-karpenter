# Changelog

## [1.0.0] - 2026-08-16

### Added
- Initial release: Karpenter controller installed with Helm, with its IRSA
  role scoped to the controller service account
- Node role with the EKS worker policies and an access entry registering it
  with the cluster
- Interruption queue with EventBridge rules for Spot reclaims, rebalance
  recommendations, instance state changes and scheduled maintenance
- Controller IAM policy scoped by cluster ownership tags, with PassRole
  limited to the node role
