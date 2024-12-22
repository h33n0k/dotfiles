FROM archlinux:latest

# Install core packages
RUN pacman -Sy --noconfirm "bash" "sudo"

# Mock user
RUN useradd -m -s /bin/bash mockeduser \
	&& echo 'mockeduser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/mockeduser \
	&& chmod 0440 /etc/sudoers.d/mockeduser

WORKDIR /home/mockeduser/dotfiles

# Install bootstrap core packages (optional)
RUN pacman -Sy --noconfirm "git" "jq" "yq"

COPY . /home/mockeduser/dotfiles/
RUN chmod +x "/home/mockeduser/dotfiles/bootstrap.sh"

USER mockeduser
CMD bash -c "/home/mockeduser/dotfiles/bootstrap.sh; exec bash"
