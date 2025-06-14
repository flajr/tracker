# Justfile
_default:
    just --list

b: build extract

build:
    podman build -t tracker-image .

extract:
    podman create --name tracker-container tracker-image
    podman cp tracker-container:/output/tracker-static ./tracker-static
    podman rm tracker-container

clean:
    podman rm -af
    podman rmi -af
