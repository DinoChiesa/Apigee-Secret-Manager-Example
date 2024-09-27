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
SECRET_ID_RSAKEY="apigee-example-rsakey-secret"
PROXY_SA_BASE="example-secretaccessor-"

# creating and deleting the SA repeatedly causes problems?
# So I need to introduce a random factor into the SA name.
# shellcheck disable=SC2002
rand_string=$(cat /dev/urandom | LC_CTYPE=C tr -cd '[:alnum:]' | head -c 6)
PROXY_SA="${PROXY_SA_BASE}${rand_string}"

maybe_import_and_deploy() {
    local thing_type=$1
    local thing_name=$2
    local proxy_sa=$3
    local dir_name

    local REV
    local need_deploy=0
    local need_import=0

    if [[ "$thing_type" == "apis" ]]; then
        dir_name="apiproxy"
    else
        dir_name="sharedflowbundle"
    fi
    printf "Checking %s %s\n" "$dir_name" "$thing_name"

    OUTFILE=$(mktemp /tmp/apigee-samples.apigeecli.out.XXXXXX)
    if apigeecli "$thing_type" get --name "$thing_name" --org "$PROJECT" --token "$TOKEN" --disable-check >"$OUTFILE" 2>&1; then
        LATESTREV=$(jq -r ".revision[-1]" "$OUTFILE")
        if [[ -z "${LATESTREV}" ]]; then
            need_import=1
        else
            if apigeecli "$thing_type" listdeploy --name "$thing_name" --org "$PROJECT" --token "$TOKEN" --disable-check >"$OUTFILE" 2>&1; then
                NUM_DEPLOYS=$(jq -r '.deployments | length' "$OUTFILE")
                if [[ $NUM_DEPLOYS -eq 0 ]]; then
                    need_deploy=1
                    REV=$LATESTREV
                fi
            else
                need_deploy=1
                REV=$LATESTREV
            fi
        fi
    else
        need_import=1
    fi

    if [[ ${need_import} -eq 1 ]]; then
        printf "Importing %s %s\n" "$dir_name" "$thing_name"
        REV=$(apigeecli "$thing_type" create bundle -f "./${thing_type}/${thing_name}/${dir_name}" -n "$thing_name" --org "$PROJECT" --token "$TOKEN" --disable-check | jq ."revision" -r)
        need_deploy=1
    fi

    if [[ ${need_deploy} -eq 1 ]]; then
        printf "Deploying %s %s\n" "$dir_name" "$thing_name"
        if [[ -n "${proxy_sa}" ]]; then
            # deploy with service account if one is provided
            local FULL_SA_EMAIL="${proxy_sa}@${PROJECT}.iam.gserviceaccount.com"
            apigeecli "$thing_type" deploy --name "$thing_name" --rev "$REV" \
                --org "$PROJECT" --env "$APIGEE_ENV" \
                --sa "${FULL_SA_EMAIL}" \
                --ovr --wait \
                --token "$TOKEN" \
                --disable-check
        else
            apigeecli "$thing_type" deploy --name "$thing_name" --rev "$REV" \
                --org "$PROJECT" --env "$APIGEE_ENV" \
                --ovr --wait \
                --token "$TOKEN" \
                --disable-check
        fi
    fi
}

maybe_import_and_deploy_apiproxy() {
    maybe_import_and_deploy "apis" "$PROXY_NAME" "$PROXY_SA"
}

check_and_maybe_create_sa() {
    local FULL_SA_EMAIL="${PROXY_SA}@${PROJECT}.iam.gserviceaccount.com"
    local OUTFILE=$(mktemp /tmp/apigee-samples.gcloud.out.XXXXXX)
    local REQUIRED_ROLE="roles/secretmanager.secretAccessor"
    if gcloud iam service-accounts describe "${FULL_SA_EMAIL}" --project="$PROJECT" --quiet >"$OUTFILE" 2>&1; then
        printf "That service account already exists.\n"
        printf "Checking for secretAccessor role....\n"

        # shellcheck disable=SC2076
        ARR=($(gcloud projects get-iam-policy "${PROJECT}" \
            --flatten="bindings[].members" \
            --filter="bindings.members:${FULL_SA_EMAIL}" | grep -v deleted | grep -A 1 members | grep role | sed -e 's/role: //'))

        if ! [[ ${ARR[*]} =~ "${REQUIRED_ROLE}" ]]; then
            echo "Adding ${REQUIRED_ROLE}"
            gcloud projects add-iam-policy-binding "${PROJECT}" \
                --member="serviceAccount:${SA_EMAIL}" \
                --role="$role" --quiet >>/dev/null 2>&1
        fi

    else
        echo "$PROXY_SA" >./.proxy_sa_name
        gcloud iam service-accounts create "$PROXY_SA" --project="$PROJECT" --quiet

        printf "There can be errors if all these changes happen too quickly, so we need to sleep a bit...\n"
        sleep 12

        printf "Granting access for that service account to ALL SECRETS in the project.\n"
        gcloud projects add-iam-policy-binding "$PROJECT" \
            --member="serviceAccount:${FULL_SA_EMAIL}" \
            --role="${REQUIRED_ROLE}" \
            --quiet >/dev/null 2>&1

        printf "\n================================================\n"
        printf "  FYI, the above does not comply with PoLA. The service account SHOULD\n"
        printf "  be granted access only to the specific secrets it needs.\n"
        printf "\n  eg,\n\n"
        printf "  gcloud secrets add-iam-policy-binding \"projects/myproject/secrets/mysecret\" %s\n" "\\"
        printf "    --member=\"serviceAccount:${FULL_SA_EMAIL}\" %s\n" "\\"
        printf "    --role=\"${REQUIRED_ROLE}\" \n"
        printf "================================================\n\n"
    fi
}

random_string() {
    local rand_string
    rand_string=$(cat /dev/urandom | LC_CTYPE=C tr -cd '[:alnum:]' | head -c 10)
    echo ${rand_string}
}

create_random_secret() {
    local rstring=$(random_string)
    local TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    local secret_value="secret-${TIMESTAMP}-${rstring}"
    printf "Creating secret %s\n" "$SECRET_ID"
    printf "${secret_value}" | gcloud secrets create "$SECRET_ID" --project="$PROJECT" --data-file=- --quiet

    printf "\nThe secret value is:\n  %s\n" "${secret_value}"
}

create_rsakey_secret() {
    printf "\nGenerating an RSA Key pair...\n"
    local private_key=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -outform PEM)
    # printf "\n%s\n" "${private_key}"
    printf "Creating secret %s\n" "$SECRET_ID_RSAKEY"
    printf "%s" "${private_key}" | gcloud secrets create "$SECRET_ID_RSAKEY" --project="$PROJECT" --data-file=- --quiet
    local TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
    local public_key_file="public-rsakey-$TIMESTAMP.pem"
    printf "Emitting public key into  %s\n" "$public_key_file"
    openssl pkey -pubout -inform PEM -outform PEM -in <(echo "$private_key") -out "$public_key_file"
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

printf "Checking and possibly Creating Service Account...(%s)\n" "${PROXY_SA}"

check_and_maybe_create_sa
maybe_import_and_deploy_apiproxy
create_random_secret
create_rsakey_secret

printf "\nAll the Apigee artifacts are successfully created.\n"
printf "\nTo try:\n"
printf "  curl -i \$apigee/${PROXY_NAME}/t1\n"
printf "\nYou should see the value that was inserted, shown above.\n"
printf "\nor, to tell the proxy to retrieve a secret by an ID and version you specify:\n "
printf "  curl -i \$apigee/${PROXY_NAME}/t2\?secretid=my-secret\&secretversion=1\n"
printf "\nor, to tell the proxy to retrieve an RSA Key from SecretManager, and sign a JWT with that key:\n"
printf "  curl -i \$apigee/${PROXY_NAME}/t3  -d ''\n"
printf "\nYou should see a signed JWT in a response header.\n"
