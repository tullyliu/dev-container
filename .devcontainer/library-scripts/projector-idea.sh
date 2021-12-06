#!/usr/bin/env bash
# Syntax: projector-idea.sh [IDEA URL] [PROJECTOR_DIR] [SDKMAN_DIR] [non-root user] [Add to rc files flag]
IDEA_URL=${1:-""}
export PROJECTOR_DIR=${2:-"/usr/local/projector"}
SDKMAN_DIR=${3:-"/usr/local/sdkman"}
USERNAME=${4:-"automatic"}
UPDATE_RC=${5:-"true"}
JAVA_VERSION=${6:-""}
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
PREREQ_PKGS="libxext6 libxrender1 libxtst6 libxi6 libfreetype6 procps"
if ! dpkg -s ${PREREQ_PKGS} > /dev/null 2>&1; then
    if [ ! -d "/var/lib/apt/lists" ] || [ "$(ls /var/lib/apt/lists/ | wc -l)" = "0" ]; then
        apt-get update
    fi
    apt-get -y install --no-install-recommends ${PREREQ_PKGS}
fi

# Install Projector
if [ ! -d "${PROJECTOR_DIR}" ]; then
    # Create sdkman group, dir, and set sticky bit
    if ! cat /etc/group | grep -e "^projector:" > /dev/null 2>&1; then
        groupadd -r projector
    fi
    usermod -a -G projector ${USERNAME}
    umask 0002
    # Install 
    mkdir -p ${PROJECTOR_DIR}/projector-server ${PROJECTOR_DIR}/download ${PROJECTOR_DIR}/ide
    git clone --depth=1 \
        -c core.eol=lf \
        -c core.autocrlf=false \
        -c fsck.zeroPaddedFilemode=ignore \
        -c fetch.fsck.zeroPaddedFilemode=ignore \
        -c receive.fsck.zeroPaddedFilemode=ignore \
        https://github.com/JetBrains/projector-server.git ${PROJECTOR_DIR}/projector-server 2>&1
    
    # Build projector server
    source ${SDKMAN_DIR}/bin/sdkman-init.sh && sdk use java ${JAVA_VERSION}  
    cd ${PROJECTOR_DIR}/projector-server 
    ./gradlew clean && ./gradlew :projector-server:distZip 

    # Download ide
    cd ${PROJECTOR_DIR}/download
    wget -q $IDEA_URL -O - | tar -xz
    find . -maxdepth 1 -type d -name * -execdir mv {} ${PROJECTOR_DIR}/ide \;
    
    # Process file layout
    find ${PROJECTOR_DIR}/projector-server/projector-server/build/distributions -maxdepth 1 -type f -name projector-server-*.zip -exec mv {} ${PROJECTOR_DIR}/projector-server.zip \;

    mv ${PROJECTOR_DIR}/projector-server/projector-server/build/distributions/projector-server.zip ${PROJECTOR_DIR}
    unzip ${PROJECTOR_DIR}/projector-server.zip -d ${PROJECTOR_DIR}
    rm ${PROJECTOR_DIR}/projector-server.zip
    find ${PROJECTOR_DIR} -maxdepth 1 -type d -name projector-server-* -exec mv {} $PROJECTOR_DIR/ide/projector-server \;
    mv /tmp/library-scripts/ide-projector-launcher.sh $PROJECTOR_DIR/ide/bin
    # Clean    
    rm -rf ${PROJECTOR_DIR}/projector-server ${PROJECTOR_DIR}/download

    chown -R :projector ${PROJECTOR_DIR}
    find ${PROJECTOR_DIR} -type d | xargs -d '\n' chmod g+s
fi


echo "Done!"
