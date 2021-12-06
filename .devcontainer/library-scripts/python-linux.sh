#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/vscode-dev-containers/blob/master/script-library/docs/python.md
#
# Syntax: ./python-debian.sh [Python Version] [Python intall path] [PIPX_HOME] [non-root user] [Update rc files flag] [install tools]

PYTHON_VERSION=${1:-"3.8.3"}
export PIPX_HOME=${3:-"/usr/local/py-utils"}
USERNAME=${4:-"automatic"}
UPDATE_RC=${5:-"true"}
INSTALL_PYTHON_TOOLS=${6:-"true"}
PYENV_HOME="/usr/local/pyenv"
set -e

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Ensure that login shells get the correct path if the user updated the PATH using ENV.
rm -f /etc/profile.d/00-restore-env.sh
echo "export PATH=${PATH//$(sh -lc 'echo $PATH')/\$PATH}" > /etc/profile.d/00-restore-env.sh
chmod +x /etc/profile.d/00-restore-env.sh

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in ${POSSIBLE_USERS[@]}; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

function updaterc() {
    if [ "${UPDATE_RC}" = "true" ]; then
        echo "Updating /etc/bash.bashrc and /etc/zsh/zshrc..."
        echo -e "$1" | tee -a /etc/bash.bashrc >> /etc/zsh/zshrc
    fi
}

export DEBIAN_FRONTEND=noninteractive

# Install prereqs if missing
PREREQ_PKGS="vim make build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev llvm libncurses5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev"
if ! dpkg -s ${PREREQ_PKGS} > /dev/null 2>&1; then
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        apt-get update
    fi
    apt-get -y install --no-install-recommends ${PREREQ_PKGS}
fi

# Install pyenv if not installed
if [ ! -d "${PYENV_HOME}" ]; then
    # Create pyenv group, dir, and set sticky bit
    if ! cat /etc/group | grep -e "^pyenv:" > /dev/null 2>&1; then
        groupadd -r pyenv
    fi
    usermod -a -G pyenv ${USERNAME}
    umask 0002
    # Install pyenv
    export PYENV_ROOT=${PYENV_HOME} && curl https://pyenv.run | bash 
    chown -R :pyenv ${PYENV_HOME}
    find ${PYENV_HOME} -type d | xargs -d '\n' chmod g+s
    # Add sourcing of pyenv into bashrc/zshrc files (unless disabled)
    updaterc "export PYENV_ROOT=${PYENV_HOME}\nexport PATH=${PYENV_HOME}/bin:\$PATH\n if command -v pyenv 1>/dev/null 2>&1; then\n  eval \"\$(pyenv init --path)\"\n eval \"\$(pyenv init -)\"\nfi"
fi

su ${USERNAME} -c "umask 0002 && export PYENV_ROOT=${PYENV_HOME} && export PATH=${PYENV_HOME}/bin:\$PATH && eval \"\$(pyenv init --path)\" && eval \"\$(pyenv init -)\" && pyenv --version  && pyenv install 2.7.18 && pyenv versions && pyenv install ${PYTHON_VERSION} && pyenv global ${PYTHON_VERSION} && pyenv versions && which python &&python -m pip install --no-cache-dir --upgrade pip"

# If not installing python tools, exit
if [ "${INSTALL_PYTHON_TOOLS}" != "true" ]; then
    echo "Done!"
    exit 0;
fi

DEFAULT_UTILS="\
    pylint \
    flake8 \
    autopep8 \
    black \
    yapf \
    mypy \
    pydocstyle \
    pycodestyle \
    bandit \
    poetry \
    virtualenv"


export PIPX_BIN_DIR=${PIPX_HOME}/bin
export PATH=${PIPX_BIN_DIR}:${PATH}


# Create pipx group, dir, and set sticky bit
if ! cat /etc/group | grep -e "^pipx:" > /dev/null 2>&1; then
    groupadd -r pipx
fi
usermod -a -G pipx ${USERNAME}
umask 0002
mkdir -p ${PIPX_BIN_DIR}
chown :pipx ${PIPX_HOME} ${PIPX_BIN_DIR}
chmod g+s ${PIPX_HOME} ${PIPX_BIN_DIR}

# Install tools
echo "Installing Python tools..."
export PYTHONUSERBASE=/tmp/pip-tmp
export PIP_CACHE_DIR=/tmp/pip-tmp/cache
su ${USERNAME} -c "umask 0002 && export PATH=${PYENV_HOME}/bin:$PATH && eval \"\$(pyenv init --path)\" && eval \"\$(pyenv init -)\" && pip install --disable-pip-version-check --no-warn-script-location  --no-cache-dir --user pipx"
/tmp/pip-tmp/bin/pipx install --pip-args=--no-cache-dir pipx
echo "${DEFAULT_UTILS}" | xargs -n 1 /tmp/pip-tmp/bin/pipx install --system-site-packages --pip-args '--no-cache-dir --force-reinstall'
rm -rf /tmp/pip-tmp

updaterc "$(cat << EOF
export PIPX_HOME="${PIPX_HOME}"
export PIPX_BIN_DIR="${PIPX_BIN_DIR}"
if [[ "\${PATH}" != *"\${PIPX_BIN_DIR}"* ]]; then export PATH="\${PATH}:\${PIPX_BIN_DIR}"; fi
EOF
)"



