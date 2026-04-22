# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# Base Image
FROM ghcr.io/ublue-os/aurora:stable

## Other possible base images include:
# FROM ghcr.io/ublue-os/bazzite:latest
# FROM ghcr.io/ublue-os/bluefin-nvidia:stable
# 
# ... and so on, here are more base images
# Universal Blue Images: https://github.com/orgs/ublue-os/packages
# Fedora base image: quay.io/fedora/fedora-bootc:41
# CentOS base images: quay.io/centos-bootc/centos-bootc:stream10

### [IM]MUTABLE /opt
## Some bootable images, like Fedora, have /opt symlinked to /var/opt, in order to
## make it mutable/writable for users. However, some packages write files to this directory,
## thus its contents might be wiped out when bootc deploys an image, making it troublesome for
## some packages. Eg, google-chrome, docker-desktop.
##
## Uncomment the following line if one desires to make /opt immutable and be able to be used
## by the package manager.

 RUN rm /opt && mkdir /opt

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

## homeserver CA built in.
# 1. copy root ca to the image
COPY certs/caddy-horst-root.crt /etc/pki/ca-trust/source/anchors/caddy-horst-root.crt

# 2. update CA-database inside of the Image
RUN update-ca-trust

# 3. make firefox accept my certs (chrome based browsers like it without)
RUN mkdir -p /usr/lib64/firefox/distribution/
COPY files/firefox/policies.json /usr/lib64/firefox/distribution/policies.json

# 4. flatpak firefox: grant cert access + import via systemd user service
COPY files/flatpak/overrides/org.mozilla.firefox /etc/flatpak/overrides/org.mozilla.firefox
COPY files/firefox/firefox-flatpak-cert-import.sh /usr/bin/firefox-flatpak-cert-import.sh
COPY files/firefox/firefox-flatpak-cert-import.service /usr/lib/systemd/user/firefox-flatpak-cert-import.service
RUN chmod +x /usr/bin/firefox-flatpak-cert-import.sh && \
    systemctl --global enable firefox-flatpak-cert-import.service
### ANTIGRAVITY
# COPY build_files/antigravity.repo /etc/yum.repos.d/antigravity.repo
# RUN dnf5 install -y antigravity && \
#    dnf5 clean all

### OS IDENTITY
# Override os-release to change system name in neofetch/fastfetch/bootc status
COPY files/os-release /usr/lib/os-release

# OCI label → used by bootc/ostree for GRUB boot entry title
LABEL org.opencontainers.image.title="Horst_OS!"

### BRANDING
# Plymouth boot screen: replace watermark (shown bottom-center during spinner)
COPY files/branding/watermark.png /usr/share/plymouth/themes/spinner/watermark.png

# KDE Plasma splash screen: replace logo in both dark and light look-and-feel themes
COPY files/branding/horst_logo.svgz /usr/share/plasma/look-and-feel/dev.getaurora.aurora.desktop/contents/splash/images/aurora_logo.svgz
COPY files/branding/horst_logo.svgz /usr/share/plasma/look-and-feel/dev.getaurora.auroralight.desktop/contents/splash/images/aurora_logo.svgz

# KDE About This System: override hardcoded "Aurora" name
COPY files/branding/kcm-about-distrorc /usr/share/kde-settings/kde-profile/default/xdg/kcm-about-distrorc

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
