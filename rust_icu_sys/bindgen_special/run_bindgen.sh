#! /bin/bash
# Copyright 2019 Google LLC
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

# A script that updates the bindgen library manually.
#
# Please refer to the file README.md
#
# Requirements:
# - bash
# - awk
# - tr
# - llvm-dev package (for llvm-config that bindgen needs)

set -eo pipefail

# The directory into which the rust bindings file will be written.  If left
# unset, the current directory is the default.
OUTPUT_DIR=${OUTPUT_DIR:-.}

# The list of unicode source headers to generate bindings for. This list is
# intended to be kept in sync with the static variable by the same name in the
# build.rs file.
readonly BINDGEN_SOURCE_MODULES=(
)

# Types for which to generate the bindings.  Expand this list if you need more.
# The syntax is regex.  This list is intended to be kept in sync with the static
# variable by the same name in the build.rs file.
readonly BINDGEN_ALLOWLIST_TYPES=(
        "UCPTrie.*"
        "UCPTrieType"
        "UCPTRIE.*"
        "UPRV.*"
)

# Functions for which to generate the bindings.  Expand this list if you need
# more.  This list is intended to be kept in sync with the static variable by
# the same name in the build.rs file.
readonly BINDGEN_ALLOWLIST_FUNCTIONS=(
        "usrc_.*"
)

readonly TOOLS_DIR="/src/icu/icu4c/source/tools/toolutil"

# Modules that are only included if present.  This is for the ICU tools, for
# example. Relative to $TOOLS_DIR.
readonly BINDGEN_TOOLS_MODULES=(
  "writesrc.h"
)

function check_requirements() {
  icu-config --version &> /dev/null || \
    (echo "The generator requires icu-config to be in PATH; see README.md"; exit 1)

  bindgen --version &> /dev/null || \
    (echo "The generator requires bindgen to be in PATH; see README.md"; exit 1)

  awk --version &> /dev/null || \
    (echo "The generator requires awk to be installed; see README.md"; exit 1)

  llvm-config --version &> /dev/null || \
    (echo "The generator requires llvm-config (package llvm-dev) to be installed; see README.md"; exit 1)
}

# Generates a temporary header file to be supplied to bindgen for binding generation.
# The file is automatically removed upon exit, so if you are debugging you may want
# to remove that part.
function generate_header_file() {
  MAIN_HEADER_FILE="$(mktemp --suffix=.h)"
  echo "MAIN_HEADER_FILE=${MAIN_HEADER_FILE}"
  trap "rm ${MAIN_HEADER_FILE}" EXIT

  readonly ICU_INCLUDE_DIR="$(icu-config --prefix)/include/unicode"

  echo "// Automatically generated by run_bindgen.sh, DO NOT EDIT. " > ${MAIN_HEADER_FILE}
  for module in ${BINDGEN_SOURCE_MODULES[@]}; do
    echo "#include \"${ICU_INCLUDE_DIR}/${module}.h\"" >> "${MAIN_HEADER_FILE}"
  done

  ls -d /src/icu

  # Optionally include the files from other headers.
  if [[ -e "${TOOLS_DIR}" ]]; then
    for module in ${BINDGEN_TOOLS_MODULES[@]}; do
      modulepath="${TOOLS_DIR}/${module}"
      if [[ -f "${modulepath}" ]]; then 
        echo "#include \"${modulepath}\"" >> "${MAIN_HEADER_FILE}"
      fi
    done
  fi
}

function main() {
  check_requirements

  generate_header_file

  # Joins all with a |, so ("a" "b") become "a|b"
  local _allowlist_types_concat="$(\
    echo ${BINDGEN_ALLOWLIST_TYPES[@]} | tr ' ' '|')"
  local _functions_concat="$(\
    echo ${BINDGEN_ALLOWLIST_FUNCTIONS[@]} | tr ' ' '|')"

  set -x 

  # Example: "67.1", "66.0.1"
  local _icu_version="$(icu-config --version)"
  # Example: "67"
  local _icu_version_major="${_icu_version%.*}"
  local _icu_version_major="${_icu_version_major%.*}"

  # Respectful code hack.
  local _allowlist="$(echo "d2hpdGVsaXN0Cg==" | base64 -d -)"


  local _output_file="${OUTPUT_DIR}/lib_${_icu_version_major}.rs"
  bindgen \
    --default-enum-style=rust \
    --no-doc-comments \
    --with-derive-default \
    --with-derive-hash \
    --with-derive-partialord \
    --with-derive-partialeq \
    --"${_allowlist}"-type="${_allowlist_types_concat}" \
    --"${_allowlist}"-function="${_functions_concat}" \
    --opaque-type="" \
    --output="${_output_file}" \
    "${MAIN_HEADER_FILE}" \
    -- \
    $(icu-config --cppflags) \
    -I ${TOOLS_DIR} \
    -I "/src/icu/icu4c/source/common"

  # This can fail for weird reasons, ignore.
  rustfmt --force "${_output_file}" || true
}

main