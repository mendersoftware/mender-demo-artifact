FROM debian:12
RUN apt update && apt install -y build-essential gcc-arm-linux-gnueabi curl unzip cmake

WORKDIR /tmp
RUN curl -f -O https://busybox.net/downloads/busybox-1.36.1.tar.bz2
RUN tar xjf busybox-1.36.1.tar.bz2
WORKDIR /tmp/busybox-1.36.1

# x86_64
RUN make distclean
RUN make -j$(nproc) defconfig
RUN make -j$(nproc)
RUN cp busybox /tmp/busybox_x86_64

# ARM
RUN make distclean
RUN env CROSS_COMPILE=arm-linux-gnueabi- LDFLAGS=-static make -j$(nproc) defconfig
RUN env CROSS_COMPILE=arm-linux-gnueabi- LDFLAGS=-static make -j$(nproc)
RUN cp busybox /tmp/busybox_armhf

ARG MENDER_ARTIFACT_VERSION=none
RUN if [ "$MENDER_ARTIFACT_VERSION" = none ]; then echo "MENDER_ARTIFACT_VERSION must be set!" 1>&2; exit 1; fi
RUN curl -f -O https://downloads.mender.io/repos/debian/pool/main/m/mender-artifact/mender-artifact_$MENDER_ARTIFACT_VERSION-1+debian+$(. /etc/os-release; echo $VERSION_CODENAME)_amd64.deb
RUN dpkg --install mender-artifact_$MENDER_ARTIFACT_VERSION-1+debian+$(. /etc/os-release; echo $VERSION_CODENAME)_amd64.deb

ARG MENDER_VERSION=none
RUN if [ "$MENDER_VERSION" = none ]; then echo "MENDER_VERSION must be set!" 1>&2; exit 1; fi
WORKDIR /tmp

# NOTE: the sed command below can be removed when upgrading to newer debian version. See:
# https://github.com/mendersoftware/mender/pull/1556
RUN curl -Lo $MENDER_VERSION.zip https://github.com/mendersoftware/mender/archive/${MENDER_VERSION}.zip; \
    unzip $MENDER_VERSION.zip; \
    cmake -S /tmp/mender-$MENDER_VERSION -B /tmp/mender-$MENDER_VERSION -D MENDER_NO_BUILD=1 || true; \
    sed -i 's|component=|component |g' /tmp/mender-$MENDER_VERSION/support/CMakeLists.txt || true; \
    make -C /tmp/mender-$MENDER_VERSION install-modules-gen;

COPY onboarding-site /data/www/localhost
WORKDIR /data/www/localhost
RUN mkdir -p htdocs
RUN cp index.html htdocs
RUN cp /tmp/busybox_armhf /tmp/busybox_x86_64 /data/www/localhost

WORKDIR /tmp
COPY state-scripts state-scripts
# Make artifact name overridable
ARG ARTIFACT_NAME=mender-demo-artifact
RUN directory-artifact-gen \
    -n $ARTIFACT_NAME \
    -t beaglebone \
    -t beaglebone-yocto \
    -t beaglebone-yocto-grub \
    -t docker-client \
    -t generic-armv6 \
    -t generic-x86_64 \
    -t qemux86-64 \
    -t raspberrypi0w \
    -t raspberrypi0-wifi \
    -t raspberrypi3 \
    -t raspberrypi4 \
    -t raspberrypi \
    -d /data/www/localhost \
    -o mender-demo-artifact.mender \
    /data/www/localhost \
    -- \
    --software-filesystem data-partition \
    --software-name mender-demo-artifact \
    --software-version ${MENDER_VERSION} \
    -s state-scripts/ArtifactInstall_Leave_50_choose_busybox_arch \
    -s state-scripts/ArtifactInstall_Leave_90_install_systemd_unit \
    -s state-scripts/ArtifactRollback_Enter_00_remove_systemd_unit

# We need to find the right architecture in the container too.
RUN state-scripts/ArtifactInstall_Leave_50_choose_busybox_arch

VOLUME /output
CMD echo "Copying artifact to /output." \
    && cp /tmp/mender-demo-artifact.mender /output \
    && chown --reference=/output /output/mender-demo-artifact.mender

EXPOSE 80

RUN ( \
    echo "To get the demo artifact, run:"; \
    echo '  docker run --rm -v $PWD/output:/output mender-demo-artifact'; \
    echo; \
    echo "To run the onboarding-site locally, run:"; \
    echo "  docker run --rm -t -p 8080:80 mender-demo-artifact /data/www/localhost/entrypoint.sh"; \
    ) 1>&2
