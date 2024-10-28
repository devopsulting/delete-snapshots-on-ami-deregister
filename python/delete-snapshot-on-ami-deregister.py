import boto3
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    ec2_cli = boto3.client("ec2")
    logger.info("Event Details: %s", json.dumps(event, indent=2))
    ami_id = event["detail"]["ImageId"]
    response = ec2_cli.describe_snapshots(OwnerIds=["self"])
    for snapshot in response["Snapshots"]:
        snap_desc = snapshot.get("Description")
        first, *middle, last = (
            snap_desc.split()
        )  # Split the snapshot description into first and last words, middle section
        if last == ami_id:
            snapshot_id = snapshot.get("SnapshotId")
            logger.info("Snapshot to be deleted: %s", snapshot_id)
            try:
                del_response = ec2_cli.delete_snapshot(
                    SnapshotId=snapshot_id,
                )
                logger.info(f"Snapshot {snapshot_id} deleted successfully")
            except Exception as e:
                return {
                    "statusCode": 500,
                    "body": f"Error deleting snapshot {snapshot_id}: {e}",
                }
    return {"statusCode": 200}
