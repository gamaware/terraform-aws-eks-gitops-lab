# Offline: the AWS provider is mocked, so no credentials or API calls are needed.
mock_provider "aws" {
  source = "../../tests/mocks"
}

variables {
  cluster_name     = "harbor-goods-test"
  min_running_pods = { storefront = 2 }
}

run "every_alarm_notifies_the_encrypted_topic" {
  command = apply

  assert {
    condition     = length(output.alarm_names) == 4
    error_message = "Expected failed-node, CPU, memory and one running-pods alarm."
  }

  assert {
    condition = alltrue(concat(
      [aws_cloudwatch_metric_alarm.failed_nodes.alarm_actions == toset([aws_sns_topic.alarms.arn])],
      [for a in aws_cloudwatch_metric_alarm.node_utilization : a.alarm_actions == toset([aws_sns_topic.alarms.arn])],
      [for a in aws_cloudwatch_metric_alarm.running_pods : a.alarm_actions == toset([aws_sns_topic.alarms.arn])],
    ))
    error_message = "Every alarm must notify the alarm topic."
  }

  assert {
    condition     = aws_sns_topic.alarms.kms_master_key_id == aws_kms_key.platform.id
    error_message = "The alarm topic must use the platform key, which grants CloudWatch access; the AWS managed SNS key does not."
  }
}

run "missing_data_is_treated_as_failure_where_silence_means_trouble" {
  command = apply

  assert {
    condition     = aws_cloudwatch_metric_alarm.failed_nodes.treat_missing_data == "breaching"
    error_message = "If Container Insights stops reporting, the failed-node alarm must fire."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.running_pods["storefront"].treat_missing_data == "breaching"
    error_message = "A namespace with no running pods reports no data; that must alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.running_pods["storefront"].threshold == 2
    error_message = "The running-pods threshold must come from min_running_pods."
  }
}

run "container_insights_logs_expire_and_are_encrypted" {
  command = apply

  assert {
    condition     = length(aws_cloudwatch_log_group.container_insights) == 4
    error_message = "All four Container Insights log groups must be pre-created."
  }

  assert {
    condition     = alltrue([for g in aws_cloudwatch_log_group.container_insights : g.retention_in_days == 365 && g.kms_key_id == aws_kms_key.platform.arn])
    error_message = "Container Insights log groups must have a retention and the platform key."
  }
}

run "no_subscription_without_an_address" {
  command = plan

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No email subscription should exist unless alarm_emails is set."
  }
}

run "rejects_a_malformed_email" {
  command = plan

  variables {
    alarm_emails = ["ops-at-example.com"]
  }

  expect_failures = [var.alarm_emails]
}
