FROM debian:11
RUN apt update
RUN apt install -y build-essential gcc-arm-linux-gnueabi curl unzip

WORKDIR /tmp
RUN curl -f -O https://busybox.net/downloads/busybox-1.30.1.tar.bz2
RUN tar xjf busybox-1.30.1.tar.bz2
WORKDIR /tmp/busybox-1.30.1

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
RUN curl -f -o /usr/bin/mender-artifact https://d1b0l86ne08fsf.cloudfront.net/mender-artifact/$MENDER_ARTIFACT_VERSION/linux/mender-artifact
RUN chmod ugo+x /usr/bin/mender-artifact

ARG MENDER_VERSION=none
RUN if [ "$MENDER_VERSION" = none ]; then echo "MENDER_VERSION must be set!" 1>&2; exit 1; fi
WORKDIR /tmp

# Hack specifically for 2.0.0: directory-artifact-gen was lacking '--' option in
# 2.0.0, which we need, so use 2.0.x.
RUN if [ $MENDER_VERSION = 2.0.0 ]; then \
    curl -Lo mender-2.0.x.zip https://github.com/mendersoftware/mender/archive/2.0.x.zip; \
    unzip mender-2.0.x.zip; \
    make -C /tmp/mender-2.0.x install-modules-gen; \
else \
    curl -Lo mender-$MENDER_VERSION.zip https://github.com/mendersoftware/mender/archive/$MENDER_VERSION.zip; \
    unzip mender-$MENDER_VERSION.zip; \
    make -C /tmp/mender-$MENDER_VERSION install-modules-gen; \
fi

COPY onboarding-site /var/www/localhost
WORKDIR /var/www/localhost
RUN mkdir -p htdocs
RUN cp index.html htdocs
RUN cp /tmp/busybox_armhf /tmp/busybox_x86_64 /var/www/localhost

WORKDIR /tmp
COPY state-scripts state-scripts
# Make artifact name overridable
ARG ARTIFACT_NAME=mender-demo-artifact
RUN directory-artifact-gen \
    -n $ARTIFACT_NAME \
    -t beaglebone \
    -t beaglebone-yocto \
    -t beaglebone-yocto-grub \
    -t generic-armv6 \
    -t generic-x86_64 \
    -t qemux86-64 \
    -t raspberrypi0w \
    -t raspberrypi0-wifi \
    -t raspberrypi3 \
    -t raspberrypi4 \
    -t raspberrypi \
    -d /var/www/localhost \
    -o mender-demo-artifact.mender \
    /var/www/localhost \
    -- \
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
    echo "  docker run --rm -t -p 8080:80 mender-demo-artifact /var/www/localhost/entrypoint.sh"; \
    ) 1>&2
