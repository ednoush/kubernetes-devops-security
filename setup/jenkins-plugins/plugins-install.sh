#!/bin/bash
 
set -euo pipefail
 
JENKINS_URL='http://localhost:8080'
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_PASS="${JENKINS_PASS:-admin}"
 
JENKINS_CRUMB=$(curl -sf --cookie-jar /tmp/cookies -u "${JENKINS_USER}:${JENKINS_PASS}" \
  "${JENKINS_URL}/crumbIssuer/api/json" | jq -r .crumb)
 
if [ -z "${JENKINS_CRUMB}" ] || [ "${JENKINS_CRUMB}" = "null" ]; then
  echo "ERROR: failed to retrieve Jenkins crumb" >&2
  exit 1
fi
 
JENKINS_TOKEN=$(curl -sf -X POST -H "Jenkins-Crumb:${JENKINS_CRUMB}" --cookie /tmp/cookies \
  "${JENKINS_URL}/me/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken?newTokenName=demo-token66" \
  -u "${JENKINS_USER}:${JENKINS_PASS}" | jq -r .data.tokenValue)
 
if [ -z "${JENKINS_TOKEN}" ] || [ "${JENKINS_TOKEN}" = "null" ]; then
  echo "ERROR: failed to retrieve Jenkins API token" >&2
  exit 1
fi
 
echo "$JENKINS_URL"
echo "$JENKINS_CRUMB"
echo "$JENKINS_TOKEN"
 
while read -r plugin; do
   [ -z "$plugin" ] && continue
   echo "........Installing ${plugin} .."
   curl -sf -X POST \
     -H "Jenkins-Crumb:${JENKINS_CRUMB}" \
     -H 'Content-Type: text/xml' \
     --data "<jenkins><install plugin='${plugin}' /></jenkins>" \
     "${JENKINS_URL}/pluginManager/installNecessaryPlugins" \
     --user "${JENKINS_USER}:${JENKINS_TOKEN}"
   echo
done < plugins.txt
 
#### installNecessaryPlugins only *queues* the downloads — wait for them to
#### actually finish before restarting, otherwise safeRestart can interrupt
#### in-flight downloads and leave plugins half-installed (or not installed at all).
echo "Waiting for plugin installation jobs to complete..."
MAX_WAIT=600   # seconds
ELAPSED=0
while true; do
  PENDING=$(curl -sf -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
    "${JENKINS_URL}/updateCenter/api/json?depth=1" \
    | jq -r '[.jobs[]? | select(.status.type == "Pending" or .status.type == "Downloading" or .status.type == "Installing")] | length')
 
  if [ "${PENDING}" -eq 0 ]; then
    echo "All plugin installation jobs finished."
    break
  fi
 
  if [ "${ELAPSED}" -ge "${MAX_WAIT}" ]; then
    echo "ERROR: timed out after ${MAX_WAIT}s waiting for plugin installs to finish (${PENDING} job(s) still pending)" >&2
    exit 1
  fi
 
  echo "  ${PENDING} job(s) still in progress, waiting..."
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done
 
FAILED=$(curl -sf -u "${JENKINS_USER}:${JENKINS_TOKEN}" \
  "${JENKINS_URL}/updateCenter/api/json?depth=1" \
  | jq -r '[.jobs[]? | select(.status.type == "Failure" or .status.type == "Fail")] | length')
 
if [ "${FAILED}" -gt 0 ]; then
  echo "ERROR: ${FAILED} plugin install job(s) failed. Check ${JENKINS_URL}/updateCenter for details." >&2
  exit 1
fi
 
#### we also need to do a restart for some plugins
echo "Triggering Jenkins safe restart to apply plugins that require it..."
curl -sf -X POST -H "Jenkins-Crumb:${JENKINS_CRUMB}" \
  "${JENKINS_URL}/safeRestart" \
  --user "${JENKINS_USER}:${JENKINS_TOKEN}"
 
#### check all plugins installed in jenkins
#
# http://<jenkins-url>/script
 
# Jenkins.instance.pluginManager.plugins.each{
#   plugin ->
#     println ("${plugin.getDisplayName()} (${plugin.getShortName()}): ${plugin.getVersion()}")
# }
 
 
#### Check for updates/errors - http://<jenkins-url>/updateCenter
 