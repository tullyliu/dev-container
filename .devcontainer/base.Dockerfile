FROM ubuntu:20.04
# [Option] Install zsh
ARG INSTALL_ZSH="true"
# [Option] Upgrade OS packages to their latest versions
ARG UPGRADE_PACKAGES="true"
# Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
COPY library-scripts/common-debian.sh /tmp/library-scripts/
RUN bash /tmp/library-scripts/common-debian.sh "${INSTALL_ZSH}" "${USERNAME}" "${USER_UID}" "${USER_GID}" "${UPGRADE_PACKAGES}" \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts


# [Option] Install Maven
ARG INSTALL_MAVEN="true"
ARG MAVEN_VERSION=""
# [Option] Install Gradle
ARG INSTALL_GRADLE="true"
ARG GRADLE_VERSION=""
ENV SDKMAN_DIR="/usr/local/sdkman"
ENV GRL_VERSION="22.0.0.2.r11-grl"
ENV PATH="${PATH}:${SDKMAN_DIR}/java/current/bin:${SDKMAN_DIR}/maven/current/bin:${SDKMAN_DIR}/gradle/current/bin"
COPY library-scripts/java-debian.sh library-scripts/maven-debian.sh library-scripts/gradle-debian.sh /tmp/library-scripts/
RUN bash /tmp/library-scripts/java-debian.sh "${GRL_VERSION}" "${SDKMAN_DIR}" "${USERNAME}" "true" \
    && if [ "${INSTALL_MAVEN}" = "true" ]; then bash /tmp/library-scripts/maven-debian.sh "${MAVEN_VERSION:-latest}" "${SDKMAN_DIR}" ${USERNAME} "true"; fi \
    && if [ "${INSTALL_GRADLE}" = "true" ]; then bash /tmp/library-scripts/gradle-debian.sh "${GRADLE_VERSION:-latest}" "${SDKMAN_DIR}" ${USERNAME} "true"; fi \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts

# install graalvm native image
RUN su vscode -c "umask 0002 && cd ${SDKMAN_DIR}/candidates/java/${GRL_VERSION}/bin && ./gu install native-image"

# Install JDK 8 - version of "" installs latest
ARG JDK8_VERSION=""
RUN su vscode -c "umask 0002 && . /usr/local/sdkman/bin/sdkman-init.sh && if [ "${JDK8_VERSION}" = "" ]; then \
        sdk install java \$(sdk ls java | grep -m 1 -o ' 8.*.hs-adpt ' | awk '{print \$NF}'); \
        else sdk install java '${JDK8_VERSION}'; fi \
        && sdk use java ${GRL_VERSION} " 


# [Option] Install Node.js
ARG INSTALL_NODE="true"
ARG NODE_VERSION="lts/*"
ENV NVM_DIR=/usr/local/share/nvm
ENV NVM_SYMLINK_CURRENT=true \
    PATH="${NVM_DIR}/current/bin:${PATH}"
COPY library-scripts/node-debian.sh /tmp/library-scripts/
RUN if [ "$INSTALL_NODE" = "true" ]; then bash /tmp/library-scripts/node-debian.sh "${NVM_DIR}" "${NODE_VERSION}" "${USERNAME}"; fi \
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts


     
# Setup default python tools in a venv via pipx to avoid conflicts
ENV PIPX_HOME=/usr/local/py-utils \
    PIPX_BIN_DIR=/usr/local/py-utils/bin
ENV PATH=${PATH}:${PIPX_BIN_DIR}
COPY library-scripts/python-linux.sh /tmp/library-scripts/
RUN bash /tmp/library-scripts/python-linux.sh "3.8.3" "/usr/local" "${PIPX_HOME}" "${USERNAME}" \ 
     && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts


ENV IDEA_URL=https://download.jetbrains.com/idea/ideaIC-2022.2.3.tar.gz \
    PROJECTOR_DIR=/usr/local/projector \
    SDKMAN_DIR=/usr/local/sdkman
COPY library-scripts/projector-idea.sh library-scripts/ide-projector-launcher.sh /tmp/library-scripts/
RUN bash /tmp/library-scripts/projector-idea.sh "${IDEA_URL}" "${PROJECTOR_DIR}" "${SDKMAN_DIR}" "${USERNAME}" "true" "${GRL_VERSION}" \ 
    && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts
# [Optional] Uncomment this section to install additional OS packages.
#RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends *** \
#     && apt-get clean -y && rm -rf /var/lib/apt/lists/* /tmp/library-scripts
