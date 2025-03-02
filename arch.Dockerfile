FROM archlinux:latest AS base

# Install core packages
RUN pacman -Sy --noconfirm base-devel bash sudo xorg-xsetroot dbus git jq yq stow && pacman -Scc --noconfirm

# Mock user
RUN useradd -m -s /bin/bash mockeduser \
	&& echo 'mockeduser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/mockeduser \
	&& chmod 0440 /etc/sudoers.d/mockeduser

WORKDIR /home/mockeduser/dotfiles
RUN chown mockeduser:mockeduser -R /home/mockeduser/dotfiles
USER mockeduser

FROM base AS final

WORKDIR /home/mockeduser/dotfiles
USER mockeduser

# Set environment variables
ENV DISPLAY=:1
ENV SHELL=/bin/bash
ENV DESKTOP=false
ENV XDG_CONFIG_HOME="/home/mockeduser/.config"
ENV XDG_CACHE_HOME="/home/mockeduser/.cache"
ENV XDG_DATA_HOME="/home/mockeduser/.local/share"

# Start DBus session
RUN export $(dbus-launch)

# Copy dotfiles
COPY --chown=mockeduser . /home/mockeduser/dotfiles

CMD bash -c "eval \$(dbus-launch --sh-syntax) && /home/mockeduser/dotfiles/bootstrap.sh --no-update --xephyr; [[ \"$DESKTOP\" == \"true\" ]] && bspwm || exec bash"
