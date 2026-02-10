locals {
    default_arguments = {
        "--job-language" = var.language
        "--job-bookmark-option" = lookup(local.bookmark_options, lower(var.bookmark))
        "--TempDir" = var.temp_dir
        "--enable-continuous-log" = "true"
        "--enable-continuous-log-filter" = "true"
        "--enable-metrics" = ""
        "--enable-job-insights" = var.enable_job_insights
        "--continuous-log-logGroup" = var.log_group
    }

    upstream_job_trigger_enabled = var.upstream_job_trigger != null ? true : false
    upstream_job_trigger_state_enabled = local.upstream_job_trigger_enabled ? var.upstream_job_trigger.upstream_job_trigger_state != null ? true : "SUCCEEDED" : false
    upstream_job_trigger_count = local.upstream_job_trigger_enabled ? len(var.upstream_job_trigger.upstream_job_trigger_name) : 0

    upstream_crawler_trigger_enabled = var.upstream_crawler_trigger != null ? true : false
    upstream_crawler_trigger_state_enabled = local.upstream_crawler_trigger_enabled ? var.upstream_crawler_trigger.upstream_crawler_trigger_state != null ? true : "SUCCEEDED" : false
    upstream_crawler_trigger_count = local.upstream_crawler_trigger_enabled ? len(var.upstream_crawler_trigger.upstream_crawler_trigger_name) : 0


    bookmark_options = {
        enabled = "job-bookmark-enable"
        disabled = "job-bookmark-disable"
        paused   = "job-bookmark-pause"
    }

    role_arn = var.role_arn == null ? data.aws_iam_role.glue_role[0].arn : var.role_arn
    glue_version = var.glue_version == "0.9" ? "2.0" : var.glue_version

    default_script_location = "s3://s3-bucket-placeholder/" # This field this field will be automatically updated by glue-job-deployer lambda

    glue_job_name = var.job_type == "pythonshell" ? join("", aws_glue_job.python_job.*.name) : join("", aws_glue_job.glue_job.*.name)
    glue_job_arn = var.job_type == "pythonshell" ? join("", aws_glue_job.python_job.*.arn) : join("", aws_glue_job.glue_job.*.arn)
    glue_job_role_arn = var.job_type == "pythonshell" ? join("", aws_glue_job.python_job.*.role_arn) : join("", aws_glue_job.glue_job.*.role_arn)

    is_python_job = var.job_type == "pythonshell" ? true : false
}