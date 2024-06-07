#!/bin/bash

# Copyright 2023-2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

EXAMPLE_NAME="secret-manager"
PROXY_NAME="example-secret-accessor-proxy"
SECRET_ID="apigee-example-secret"
PROXY_SA_BASE="example-secretaccessor-"
#PROXY_SA_BASE="apigee-example-secret-accessor"

remove_access() {
    local FULL_SA_EMAIL="${PROXY_SA}@${PROJECT}.iam.gserviceaccount.com"
    local role="roles/secretmanager.secretAccessor"

    printf "Checking access...\n"
    # shellcheck disable=SC2207
    local members=($(gcloud projects get-iam-policy "$PROJECT" --filter="bindings.role:$role" --flatten="bindings[].members" --format='value[](bindings.members)' | grep "serviceAccount:" | grep "$SA_NAME_PREFIX"))

    for member in "${members[@]}"; do
        printf "  Removing IAM binding for %s\n" "$member"
        gcloud projects remove-iam-policy-binding "${PROJECT}" \
            --member="$member" \
            --role="$role" \
            --all --quiet >>/dev/null
    done
}

delete_secret() {
    if gcloud secrets describe "$SECRET_ID" --project="$PROJECT" --quiet >/dev/null 2>&1; then
        printf "Deleting that secret (%s)...\n" "${SECRET_ID}"
        gcloud secrets delete "$SECRET_ID" --project="$PROJECT" --quiet
    else
        printf "That secret (%s) does not exist.\n" "${SECRET_ID}"
    fi
}

remove_sa() {
    printf "Checking for service accounts like (%s*)\n" "${PROXY_SA_BASE}"
    # shellcheck disable=SC2207
    ARR=($(gcloud iam service-accounts list --project="$PROJECT" --quiet --format='value[](email)' | grep "$PROXY_SA_BASE"))
    if [[ ${#ARR[@]} -gt 0 ]]; then
        for sa in "${ARR[@]}"; do
            printf "Deleting service account %s\n" "${sa}"
            gcloud --quiet iam service-accounts delete "${sa}" --project="$PROJECT"
        done
    else
        printf "Found none.\n"
    fi

    # local FULL_SA_EMAIL="${PROXY_SA}@${PROJECT}.iam.gserviceaccount.com"
    # if gcloud iam service-accounts describe "${FULL_SA_EMAIL}" --quiet >/dev/null 2>&1; then
    #     printf "deleting the service account (%s)\n" "${FULL_SA_EMAIL}"
    #     gcloud iam service-accounts delete "${FULL_SA_EMAIL}" --quiet
    # else
    #     printf "That service account (%s) does not exist.\n" "${FULL_SA_EMAIL}"
    # fi
}

delete_apiproxy() {
    local proxy_name=$1
    printf "Checking Proxy %s\n" "${proxy_name}"
    if apigeecli apis get --name "$proxy_name" --org "$PROJECT" --token "$TOKEN" --disable-check >/dev/null 2>&1; then
        OUTFILE=$(mktemp /tmp/apigee-samples.apigeecli.out.XXXXXX)
        if apigeecli apis listdeploy --name "$proxy_name" --org "$PROJECT" --token "$TOKEN" --disable-check >"$OUTFILE" 2>&1; then
            NUM_DEPLOYS=$(jq -r '.deployments | length' "$OUTFILE")
            if [[ $NUM_DEPLOYS -ne 0 ]]; then
                echo "Undeploying ${proxy_name}"
                for ((i = 0; i < NUM_DEPLOYS; i++)); do
                    ENVNAME=$(jq -r ".deployments[$i].environment" "$OUTFILE")
                    REV=$(jq -r ".deployments[$i].revision" "$OUTFILE")
                    apigeecli apis undeploy --name "${proxy_name}" --env "$ENVNAME" --rev "$REV" --org "$PROJECT" --token "$TOKEN" --disable-check
                done
            else
                printf "  There are no deployments of %s to remove.\n" "${proxy_name}"
            fi
        fi
        [[ -f "$OUTFILE" ]] && rm "$OUTFILE"

        echo "Deleting proxy ${proxy_name}"
        apigeecli apis delete --name "${proxy_name}" --org "$PROJECT" --token "$TOKEN" --disable-check

    else
        printf "  The proxy %s does not exist.\n" "${proxy_name}"
    fi
}

MISSING_ENV_VARS=()
[[ -z "$PROJECT" ]] && MISSING_ENV_VARS+=('PROJECT')
[[ -z "$APIGEE_ENV" ]] && MISSING_ENV_VARS+=('APIGEE_ENV')

[[ ${#MISSING_ENV_VARS[@]} -ne 0 ]] && {
    printf -v joined '%s,' "${MISSING_ENV_VARS[@]}"
    printf "You must set these environment variables: %s\n" "${joined%,}"
    exit 1
}

TOKEN=$(gcloud auth print-access-token)

printf "deleting the Apigee proxy [%s]...\n" "$PROXY_NAME"
delete_apiproxy "$PROXY_NAME"

remove_access

delete_secret

remove_sa

printf "\nAll the Apigee artifacts should have been removed.\n"
