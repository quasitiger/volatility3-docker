FROM scratch

ADD alpine-minirootfs-3.21.3-x86_64.tar.gz /

ARG GIT_TAG_VOLATILITY3=v2.11.0
ARG GIT_TAG_VOLATILITY3_COMMUNITY=master
ARG INSTALL_GROUP=ci
ARG INSTALL_USER=unprivileged
ARG INSTALL_PREFIX=/usr/local

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    PYTHONUNBUFFERED=1 \
    PATH=/usr/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

VOLUME ["/tmp", "/var/tmp"]

# Create user/group
RUN addgroup -S "${INSTALL_GROUP}" && \
    adduser -DG -S "${INSTALL_USER}" -G "${INSTALL_GROUP}" -g "Unprivileged user"

# Install runtime and build dependencies
RUN apk add --no-cache \
        bat \
        capstone \
        dumb-init \
        less \
        py3-capstone \
        py3-pefile \
        py3-pip \
        py3-pycryptodome \
        py3-pygit2 \
        python3 && \
    apk add --no-cache --virtual stage \
        gcc \
        git \
        libusb-dev \
        linux-headers \
        make \
        musl-dev \
        python3-dev

# Install yara-python
WORKDIR /usr/local/lib
COPY --chown=unprivileged:ci /stage/yara-python yara-python
WORKDIR /usr/local/lib/yara-python
RUN python3 setup.py install && \
    find . -type d -exec chmod 0755 {} \; && \
    find . -type f -exec chmod 0644 {} \;

# Clone and install volatility3
WORKDIR /usr/local/lib
RUN git clone --branch="${GIT_TAG_VOLATILITY3}" --depth=1 --single-branch https://github.com/volatilityfoundation/volatility3.git
WORKDIR /usr/local/lib/volatility3
RUN if [ "${GIT_TAG_VOLATILITY3}" = "develop" ]; then \
        python3 -m pip install --break-system-packages build && \
        python3 -m build; \
    else \
        python3 -m pip install --break-system-packages --requirement requirements.txt && \
        python3 setup.py install; \
    fi && \
    chmod 0755 vol.py volatility3/framework/symbols/windows/pdbconv.py && \
    for destination in v3 vol vol3 volatility volatility3; do \
        ln -sf "${INSTALL_PREFIX}/lib/volatility3/vol.py" "${INSTALL_PREFIX}/bin/$destination"; \
    done && \
    ln -sf "${INSTALL_PREFIX}/lib/volatility3/volatility3/framework/symbols/windows/pdbconv.py" "${INSTALL_PREFIX}/bin/pdbconv"

# Install community plugins
WORKDIR /usr/local/share/volatility3/plugins
RUN git clone --branch="${GIT_TAG_VOLATILITY3_COMMUNITY}" --depth=1 --single-branch https://github.com/volatilityfoundation/community3.git

# Remove build dependencies
RUN apk del stage

# Copy symbols
WORKDIR /usr/local/lib/volatility3/volatility3/symbols
COPY /stage/linux.zip linux.zip
COPY /stage/mac.zip mac.zip
COPY /stage/windows.zip windows.zip
COPY /stage/symbols/symbols/windows windows
RUN find . -type d -exec chmod 0777 {} \; && \
    find . -type f -exec chmod 0666 {} \; && \
    find /usr/lib/python3* -type d -name symbols -exec chmod 0777 {} \;

# Pre-cache
RUN volatility3 -vvv frameworkinfo.FrameworkInfo && \
    mkdir -p /home/${INSTALL_USER}/.cache/volatility3 && \
    cp ~/.cache/volatility3/identifier.cache /home/${INSTALL_USER}/.cache/volatility3/ && \
    chown -R "${INSTALL_USER}:${INSTALL_GROUP}" /home/${INSTALL_USER}/.cache

# Aliases
COPY --chown=root:root assets/aliases.sh /etc/profile.d/

# Entry and run
WORKDIR /usr/local
USER unprivileged
ENTRYPOINT ["/usr/bin/dumb-init", "--", "volatility3"]
CMD ["--help"]

# Labels
ARG PRODUCT_AUTHOR=sk4la <quasitiger@gmail.com>
ARG PRODUCT_REPOSITORY=https://github.com/quasitiger/volatility3-docker
ARG PRODUCT_BUILD_DATE="$(date +%F)"
#ARG PRODUCT_BUILD_COMMIT=023ac2479be49559dd7350df81ffd4d7aaebad1c

LABEL image.author="${PRODUCT_AUTHOR}" \
      image.repository="${PRODUCT_REPOSITORY}" \
      image.date="${PRODUCT_BUILD_DATE}"
      #image.commit="${PRODUCT_BUILD_COMMIT}"