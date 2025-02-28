FROM archlinux:latest AS base

# Install core packages
RUN pacman -Sy --noconfirm bash sudo git jq yq stow && pacman -Scc --noconfirm

# Mock user
RUN useradd -m -s /bin/bash mockeduser \
	&& echo 'mockeduser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/mockeduser \
	&& chmod 0440 /etc/sudoers.d/mockeduser

WORKDIR /home/mockeduser/dotfiles
USER mockeduser

FROM base AS final

WORKDIR /home/mockeduser/dotfiles
USER mockeduser

# Copy dotfiles
COPY --chown=mockeduser . /home/mockeduser/dotfiles

CMD bash -c "/home/mockeduser/dotfiles/bootstrap.sh; exec bash"
