#!/bin/bash

url="https://app.harness.io/gateway/api/graphql?accountId=${app.accountId}"
auth_header="x-api-key: ${secrets.getValue("gabs-kms-api-key")}"
content_header="Content-Type: application/json"
pipeline_id="${input_pipeline_id}"
application_id=$(echo "${deploymentUrl}" | sed -rn 's/.*\/app\/(.+)\/pipeline-execution\/.*/\1/p')
current_pipeline_artifact_version="${artifact.buildNo}"

function getOlderApprovalPendingExecutions() {
    data_raw_query='{"query":"{\n  executions(limit: 5, filters: [{status: {operator: EQUALS, values: [\"PAUSED\"]}}, {pipeline: {operator: EQUALS, values: [\"'$1'\"]}}]) {\n    pageInfo {\n      limit\n      offset\n      total\n    }\n    nodes {\n      id\n      application {\n        id\n        name\n      }\n      ... on PipelineExecution {\n        pipeline {\n          id\n          name\n        }\n        memberExecutions {\n          nodes {\n            id\n            ... on WorkflowExecution {\n              workflow {\n                id\n                name\n              }\n              artifacts {\n                id\n                artifactSource {\n                  id\n                  name\n                  artifacts(limit: 100) {\n                    nodes {\n                      buildNo\n                    }\n                  }\n                }\n                buildNo\n              }\n              outcomes {\n                nodes {\n                  ... on DeploymentOutcome {\n                    environment {\n                      id\n                      name\n                    }\n                    service {\n                      id\n                      name\n                    }\n                  }\n                }\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}\n","variables":{}}'
    data=$(curl --location --request POST "$url" -H "$content_header" -H "$auth_header" --data-raw "$data_raw_query")

    all_pending_executions=$(echo $data | jq '[.data.executions.nodes[] | select(.memberExecutions.nodes[0].artifacts[0].buildNo<"'$current_pipeline_artifact_version'") | {execution_id: .id, application_id: .application.id, pipeline_id: .pipeline.id, service_id: .memberExecutions.nodes[0].outcomes.nodes[0].service.id, environment_id: .memberExecutions.nodes[0].outcomes.nodes[0].environment.id, artifact_id: .memberExecutions.nodes[0].artifacts[0].id, artifact_source_id: .memberExecutions.nodes[0].artifacts[0].artifactSource.id, artifact_version: .memberExecutions.nodes[0].artifacts[0].buildNo, artifact_name: .memberExecutions.nodes[0].artifacts[0].artifactSource.name, all_available_artifacts: [.memberExecutions.nodes[0].artifacts[0].artifactSource.artifacts.nodes[].buildNo]}]')

    echo $all_pending_executions

}

function abortOlderApprovalPendingExecutions() {
    execution_ids_arr=($(echo $1 | jq -r '.[].execution_id'))
 
    for exec_id in "${execution_ids_arr[@]}"
    do
      data_raw_query='{"query":"{\n  approvalDetails(applicationId: \"'$application_id'\", executionId: \"'$exec_id'\") {\n    approvalDetails {\n      approvalId\n      approvalType\n      stepName\n      stageName\n      startedAt\n      triggeredBy {\n        name\n        email\n      }\n      willExpireAt\n      ... on UserGroupApprovalDetails {\n        approvers\n        approvalId\n        approvalType\n        stepName\n        stageName\n        startedAt\n        executionId\n        triggeredBy {\n          name\n          email\n        }\n        willExpireAt\n        variables {\n          name\n          value\n        }\n      }\n      ... on ShellScriptDetails {\n        approvalId\n        approvalType\n        retryInterval\n        stageName\n        stepName\n        startedAt\n        triggeredBy {\n          email\n          name\n        }\n        willExpireAt\n      }\n      ... on SNOWApprovalDetails {\n        approvalCondition\n        approvalId\n        approvalType\n        currentStatus\n        rejectionCondition\n        stageName\n        startedAt\n        stepName\n        ticketType\n        ticketUrl\n        triggeredBy {\n          email\n          name\n        }\n        willExpireAt\n      }\n      ... on JiraApprovalDetails {\n        approvalCondition\n        approvalId\n        approvalType\n        currentStatus\n        issueKey\n        issueUrl\n        rejectionCondition\n        stepName\n        stageName\n        startedAt\n        triggeredBy {\n          email\n          name\n        }\n        willExpireAt\n      }\n    }\n  }\n}","variables":{}}'

      #echo "$data_raw_query"
      #echo "Deployment URL: ${deploymentUrl}"
      #echo "Application ID: $application_id"
      data=$(curl --location --request POST "$url" -H "$content_header" -H "$auth_header" --data-raw "$data_raw_query")

      approval_id=$(echo $data | jq -r '.data.approvalDetails.approvalDetails[].approvalId')

      echo "Approval ID: $approval_id"

      deletion_mutation_query='{"query":"mutation {\n approveOrRejectApprovals(input: {\n  action: REJECT\n  approvalId: \"'$approval_id'\"\n  applicationId: \"'$application_id'\"\n  comments: \"Testing\"\n  executionId: \"'$exec_id'\"\n  clientMutationId: \"testing\"\n  })\n  {\n  success\n  clientMutationId\n  }\n}","variables":{}}'
      deletion_mutation_exec=$(curl --location --request POST "$url" -H "$content_header" -H "$auth_header" --data-raw "$deletion_mutation_query")

      echo "$deletion_mutation_exec"

    done

}

function main() {
    all_pending_executions=$(getOlderApprovalPendingExecutions $pipeline_id)
    abortOlderApprovalPendingExecutions "$all_pending_executions"
}

main