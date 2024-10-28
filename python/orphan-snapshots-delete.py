import boto3
import json
import botocore.exceptions as ClientError


def lambda_handler(event, context):
    ec2_cli = boto3.client("ec2")
    response = ec2_cli.describe_snapshots(OwnerIds=["self"], DryRun=False)
    snapshot_volume_ids = []
    snapshot_id = []
    for each_snapshot in response["Snapshots"]:
        try:
            volume_stat = ec2_cli.describe_volume_status(
                VolumeIds=[each_snapshot["VolumeId"]], DryRun=False
            )
        except ec2_cli.exceptions.ClientError as e:
            if e.response["Error"]["Code"] == "InvalidVolume.NotFound":
                snapshot_id.append(each_snapshot["SnapshotId"])
            else:
                raise e

    if snapshot_id:
        for each_snap in snapshot_id:
            try:
                ec2_cli.delete_snapshot(
                    SnapshotId=each_snap
                )
                print(f"Deleted SnapshotId {each_snap}")
            except ClientError as e:
                return {
                    "statusCode": 500,
                    "body": f"Error deleting snapshot {each_snap}: {e}",
                }
        
        return {"statusCode": 200}