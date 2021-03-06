#!/bin/bash
OCTOOLSBIN=$(dirname $0)

# =================================================================================================================
# Validation:
# -----------------------------------------------------------------------------------------------------------------
_component_name=${1}
if [ -z "${_component_name}" ]; then
  echo -e \\n"Missing parameter!"\\n
  exit 1
fi
# -----------------------------------------------------------------------------------------------------------------
# Initialization:
# -----------------------------------------------------------------------------------------------------------------
# Components can specify settings overrides ...
# TODO:
# Refactor how the component level overrides are loaded.
# Load them like the Parameter overrides loaded from the PARAM_OVERRIDE_SCRIPT
if [ -f ${_componentSettingsFileName} ]; then
  echo -e "Loading component level settings from ${PWD}/${_componentSettingsFileName} ..."
  . ${_componentSettingsFileName}
fi

if [ -f ${OCTOOLSBIN}/ocFunctions.inc ]; then
  . ${OCTOOLSBIN}/ocFunctions.inc
fi

# Check for dependancies
JQ_EXE=jq
if ! isInstalled ${JQ_EXE}; then
    echoWarning "The ${JQ_EXE} executable is required and was not found on your path."

  cat <<-EOF
	The recommended approach to installing the required package(s) is to use either [Homebrew](https://brew.sh/) (MAC) 
  or [Chocolatey](https://chocolatey.org/) (Windows).

  Windows:
    - chocolatey install jq

  MAC:
    - brew install jq

EOF
    exit 1
fi

# Turn on debugging if asked
if [ ! -z "${DEBUG}" ]; then
  set -x
fi

# -----------------------------------------------------------------------------------------------------------------
# Configuration:
# -----------------------------------------------------------------------------------------------------------------
# Local params file path MUST be relative...Hack!
LOCAL_PARAM_DIR=${PROJECT_OS_DIR}

# -----------------------------------------------------------------------------------------------------------------
# Functions:
# -----------------------------------------------------------------------------------------------------------------
generateConfigs() {
  # Get list of JSON files - could be in multiple directories below
  if [ -d "${TEMPLATE_DIR}" ]; then
    DEPLOYS=$(getDeploymentTemplates ${TEMPLATE_DIR})
  fi

  for deploy in ${DEPLOYS}; do
    echo -e \\n\\n"Processing deployment configuration; ${deploy} ..."

    _template="${deploy}"
    _template_basename=$(getFilenameWithoutExt ${deploy})
    _deploymentConfig="${_template_basename}${DEPLOYMENT_CONFIG_SUFFIX}"
    PARAM_OVERRIDE_SCRIPT="${_template_basename}.overrides.sh"

    if [ ! -z "${PROFILE}" ]; then
      _paramFileName="${_template_basename}.${PROFILE}"
    else
      _paramFileName="${_template_basename}"
    fi

    PARAMFILE="${_paramFileName}.param"
    ENVPARAM="${_paramFileName}.${DEPLOYMENT_ENV_NAME}.param"
    if [ ! -z "${APPLY_LOCAL_SETTINGS}" ]; then
      LOCALPARAM="${LOCAL_PARAM_DIR}/${_paramFileName}.local.param"
    fi
    
    if [ -f "${PARAMFILE}" ]; then
      PARAMFILE="--param-file=${PARAMFILE}"
    else
      PARAMFILE=""
    fi

    if [ -f "${ENVPARAM}" ]; then
      ENVPARAM="--param-file=${ENVPARAM}"
    else
      ENVPARAM=""
    fi

    if [ -f "${LOCALPARAM}" ]; then
      LOCALPARAM="--param-file=${LOCALPARAM}"
    else
      LOCALPARAM=""
    fi
    
    # Parameter overrides can be defined for individual deployment templates at the root openshift folder level ...
    if [ -f ${PARAM_OVERRIDE_SCRIPT} ]; then
      if [ -z "${SPECIALDEPLOYPARM}" ]; then
        echo -e "Loading parameter overrides for ${deploy} ..."
        SPECIALDEPLOYPARM=$(${PWD}/${PARAM_OVERRIDE_SCRIPT})
      else
        echo -e "Adding parameter overrides for ${deploy} ..."
        SPECIALDEPLOYPARM="${SPECIALDEPLOYPARM} $(${PWD}/${PARAM_OVERRIDE_SCRIPT})"
      fi
    fi

    if [ ${OC_ACTION} = "replace" ]; then
      echoWarning "Preparing deployment configuration for update/replace, removing any 'Secret' objects so existing values are left untouched ..."
      oc process --filename=${_template} ${SPECIALDEPLOYPARM} ${LOCALPARAM} ${ENVPARAM} ${PARAMFILE} \
      | jq 'del(.items[] | select(.kind== "Secret"))' \
      > ${_deploymentConfig}
      exitOnError
    elif [ ${OC_ACTION} = "create" ]; then
      oc process --filename=${_template} ${SPECIALDEPLOYPARM} ${LOCALPARAM} ${ENVPARAM} ${PARAMFILE} > ${_deploymentConfig}
      exitOnError
    else
      echoError "\nUnrecognized OC_ACTION, ${OC_ACTION}.  Unable to process template.\n"
      exit 1
    fi
  
    if [ ! -z "${SPECIALDEPLOYPARM}" ]; then
      unset SPECIALDEPLOYPARM
    fi      
  done
}
# =================================================================================================================

# =================================================================================================================
# Main Script:
# -----------------------------------------------------------------------------------------------------------------
# Switch to desired project space ...
switchProject
exitOnError

echo -e "Removing dangling configuration files ..."
cleanConfigs
cleanOverrideParamFiles

echo -e \\n"Generating deployment configuration files ..."
generateConfigs

echo -e \\n\\n"Removing temporary param override files ..."
cleanOverrideParamFiles

if [ -z ${GEN_ONLY} ]; then
  echo -e \\n"Deploying deployment configuration files ..."
  deployConfigs
fi

# Delete the configuration files if the keep command line option was not specified.
if [ -z "${KEEPJSON}" ]; then
  echo -e \\n"Removing temporary deployment configuration files ..."
  cleanConfigs
fi
# =================================================================================================================
