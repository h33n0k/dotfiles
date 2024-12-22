FROM debian:latest

# Install core packages
RUN apt-get update && apt-get install -y \
	"bash" "sudo" "curl" \
	&& apt-get clean

# Mock user
RUN useradd -m -s /bin/bash mockeduser \
	&& echo 'mockeduser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/mockeduser \
	&& chmod 0440 /etc/sudoers.d/mockeduser

WORKDIR /home/mockeduser/dotfiles
RUN chown -R mockeduser:mockeduser /home/mockeduser

COPY . /home/mockeduser/dotfiles/
RUN chmod +x "/home/mockeduser/dotfiles/bootstrap.sh"

USER mockeduser
CMD bash -c "/home/mockeduser/dotfiles/bootstrap.sh; exec bash"
