FROM debian:13
RUN apt update && apt install -y build-essential curl unzip cmake

## x86_64
RUN apt install -y busybox
RUN cp /usr/bin/busybox /tmp/busybox_x86_64

# Add architectures
RUN dpkg --add-architecture arm64
RUN dpkg --add-architecture armhf
RUN apt update -y

## ARM 64 bits
RUN apt install -y busybox:arm64
RUN cp /usr/bin/busybox /tmp/busybox_arm64

## ARM 32 bits
RUN apt install -y busybox:armhf
RUN cp /usr/bin/busybox /tmp/busybox_armhf

ARG MENDER_ARTIFACT_VERSION=none
RUN if [ "$MENDER_ARTIFACT_VERSION" = none ]; then echo "MENDER_ARTIFACT_VERSION must be set!" 1>&2; exit 1; fi
RUN curl -f -O https://downloads.mender.io/repos/workstation-tools/pool/main/m/mender-artifact/mender-artifact_$MENDER_ARTIFACT_VERSION-1+debian+$(. /etc/os-release; echo $VERSION_CODENAME)_amd64.deb
RUN apt install -y ./mender-artifact_$MENDER_ARTIFACT_VERSION-1+debian+$(. /etc/os-release; echo $VERSION_CODENAME)_amd64.deb

ENV MENDER_VERSION=master
WORKDIR /tmp

RUN curl -Lo $MENDER_VERSION.zip https://github.com/mendersoftware/mender/archive/${MENDER_VERSION}.zip; \
    unzip $MENDER_VERSION.zip; \
    cmake -S /tmp/mender-$MENDER_VERSION -B /tmp/mender-$MENDER_VERSION -D MENDER_NO_BUILD=1 || true; \
    make -C /tmp/mender-$MENDER_VERSION install-modules-gen;

COPY onboarding-site /data/www/localhost
WORKDIR /data/www/localhost
RUN mkdir -p htdocs
RUN cp index.html htdocs
RUN cp /tmp/busybox_x86_64 /tmp/busybox_armhf /tmp/busybox_arm64 /data/www/localhost

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
    -t raspberrypi3_64 \
    -t raspberrypi4 \
    -t raspberrypi4_64 \
    -t raspberrypi5 \
    -t raspberrypi5_64 \
    -t raspberrypi \
    -d /data/www/localhost \
    -o mender-demo-artifact.mender \
    /data/www/localhost \
    -- \
    --software-filesystem data-partition \
    --software-name mender-demo-artifact \
    --software-version ${MENDER_ARTIFACT_VERSION} \
    -s state-scripts/ArtifactInstall_Leave_50_choose_busybox_arch \
    -s state-scripts/ArtifactInstall_Leave_90_install_systemd_unit \
    -s state-scripts/ArtifactRollback_Enter_00_remove_systemd_unit

# We need to find the right architecture in the container too.
RUN state-scripts/ArtifactInstall_Leave_50_choose_busybox_arch

VOLUME /output
CMD ["sh", "-c", "echo 'Copying artifact to /output.' && cp /tmp/mender-demo-artifact.mender /output && chown --reference=/output /output/mender-demo-artifact.mender"]

EXPOSE 80

RUN ( \
    echo "To get the demo artifact, run:"; \
    echo '  docker run --rm -v $PWD/output:/output mender-demo-artifact'; \
    echo; \
    echo "To run the onboarding-site locally, run:"; \
    echo "  docker run --rm -t -p 8080:80 mender-demo-artifact /data/www/localhost/entrypoint.sh"; \
    ) 1>&2
