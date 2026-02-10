#---------------------------------------
# Global Variables
#---------------------------------------

variable "name" {
    type = "string"
    description = "The name you assign to this job. It must be unique in your account. Any trigger created by this module will use this name as prefix"
}

variable "tags" {
    default = {}
    type = map(string)
}

#----------------------------------------
# AWS Glue Job Variables
#----------------------------------------

variable "temp_dir" {
    type = string
    description = "(Required) Specifies an AWS S3 path to a bucket that can be used as a temporary directory for the job"
}

variable "max_capacity" {
    type = number
    default = 0.0625
    description = "(Optional) The maximum number of Glue data processing units (DPUs) that can be allocated when this job runs. Valid values are: 1.0 or 0.0625"
    
    validation {
        condition = var.max_capacity == 1.0 || var.max_capacity == 0.0625
        error_message = "max_capacity must be either 1.0 or 0.0625"
    }
}

variable "number_of_workers" {
    type = number
    default = 2
    description = "(Optional) The number of workers of a defined worker type that are allocated when this job runs. Default value: 2"
}

variable "worker_type" {
    type = string
    default = "Standard"
    description = "(Optional) The type of predefined worker that is allocated when this job runs. Valid values are: G.1X, G.2X, Standard. Default value: Standard"
    
    validation {
        condition = contains(["G.1X", "G.2X", "Standard"], var.worker_type)
        error_message = "worker_type must be one of: G.1X, G.2X, Standard"
    }
}

variable "log_group" {
    type = string
    default = "/aws-glue/jobs/logs-v2"
    description = "Specifies a custom Amazon Cloudwatch log group name for a job enabled for continuous logging"
}

variable "role_arn" {
    type = string
    default = null
    description = "(Optional) The ARN of the IAM role associated with this job. If not provided, then new role will be AWSGlueServiceRole-${var.environment}-tf"
}

variable "connections" {
    type = list(string)
    default = ["PrivateSubnet01-NetworkConnection", "PrivateSubnet02-NetworkConnection"]
    description = "(Optional) A list of connections to use for this job. Default value: [\"PrivateSubnet01-NetworkConnection\", \"PrivateSubnet02-NetworkConnection\"]"
}

variable "language" {
    type = string
    default = "python"
    description = "(Optional) The programming language used to write the job script. Valid values are: python, scala. Default value: python"
}

variable "bookmark" {
    type = string
    default = "disabled"
    description = "Controls the bookmark of a job. Valid values are: enabled, disabled and paused. Default value: disabled"
}

variable "glue_version" {
    type = string
    default = "4.0"
    description = "The version of glue to use. The version must be 1.0 or higher"
}

variable "description" {
    type = string
    default = ""
    description = "(Optional) A description of the job"
}

variable "max_retries" {
    type = number
    default = 0
    description = "(Optional) The maximum number of times to retry this job after a job run fails. Default value: 0"
}

variable "timeout" {
    type = number
    default = null
    description = "(Optional) The job timeout in minutes. Default value: 2880 (48 hours) for a regular Gkue ETL. No Job timeout is defined for Glue Streaming"
}

variable max_concurrent {
    type = number
    default = 1
    description = "(Optional) The maximum number of concurrent runs allowed for this job. Default value: 1"
}

variable "enable_job_insights" {
    type = bool
    default = null
    description = "(Optional) Whether to enable job insights for this job."
}

variable "arguments" {
    type = map(string)
    default = {}
    description = "Additional job arguments like --continuous-log-logGroup, --enable-job-insights and more. Default value: {}"
}

variable "security_configuration_name" {
    type = string
    default = null
    description = "(Optional) The name of the security configuration to be used with this job. If not provided, then no security configuration will be used"
}

#----------------------------------------
# AWS Glue Trigger Variables
#----------------------------------------

variable "on_demand" {
    type = bool
    default = false
    description = "(Optional) If true, the job will have ON_DEMAND trigger. Default value: false"
}

variable "cron_schedule" {
    default = null
    description = "(Optional) The cron schedule for the trigger. Example : cron(15 12 * * ? *)"
}

variable "upstream_job_trigger" {
    type = object(
        {
            upstream_job_trigger_name = list(string)
            upstream_job_trigger_state = list(string)
        }
    )
    default = null
    description = "(Optional) Name: Populate this with the names of upstream glue jobs to create a CONDITIONAL trigger. Can be a single or multiple. State: Set the trigger state for the provided triggers. Can be single or multiple. Valid values: SUCCEEED, STOPPED, TIMEOUT, FAILED. Defaults to SUCCEEDED."
}

variable "upstream_crawler_trigger" {
    type = object(
        {
            upstream_job_trigger_name = list(string)
            upstream_job_trigger_state = list(string)
        }
    )
    default = null
    description = "(Optional) Name: Populate this with the names of upstream glue crawlers to create a CONDITIONAL trigger. Can be a single or multiple. State: Set the trigger state for the provided triggers. Can be single or multiple. Valid values: SUCCEEED, STOPPED, TIMEOUT, FAILED. Defaults to SUCCEEDED."
}

variable "workflow_name" {
    type = string
    default = null
    description = "(Optional) The name of the workflow to which this job belongs. A trigger must be created by populating 'on_demand' or 'cron_schedule' or 'upstream_job_trigger' or 'upstream_crawler_trigger' for a job to be associated with this workflow"
}

variable "job_type" {
    type = string
    default = "glueetl"
    description = "(Optional) The type of job. Valid values are: glueetl, gluestreaming or pythonshell. Default value: glueetl"
    
    validation {
        condition = var.job_type == "glueetl" || var.job_type == "gluestreaming" || var.job_type == "pythonshell"
        error_message = "job_type valid values are: glueetl, gluestreaming or pythonshell"
    }
}

variable "python_version" {
    type = string
    default = "3"
    description = "(Optional) The Python version to use for the job. Default value: 3"
}

variable "suppress_suffix" {
    type = bool
    default = false
    description = "(Optional) Specifies whether to suppress appending a random suffix at the end of the generated name. Default value: false"
}

variable "execution_class" {
    type = string
    default = "STANDARD"
    description = "(Optional) The execution class for the job. Valid values are: STANDARD, FLEX. Default value: STANDARD"
    validation {
        condition = contains(["STANDARD", "FLEX"], var.execution_class)
        error_message = "execution_class must be one of: STANDARD, FLEX"
    }
}