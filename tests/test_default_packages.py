from distutils.version import StrictVersion
import subprocess
import pytest
import testinfra  # type: ignore
from testinfra.host import Host  # type: ignore


# scope='session' uses the same cozntainer for all the tests;
# scope='function' uses a new container per test function.
# adapted from https://testinfra.readthedocs.io/en/latest/examples.html#test-docker-images
@pytest.fixture(scope="session")
def host(request):
    subprocess.check_call(["docker", "build", "-t", "test-image", "."])
    docker_id = (
        subprocess.check_output(
            ["docker", "run", "-td", "--entrypoint", "/bin/cat", "test-image"]
        )
        .decode()
        .strip()
    )
    yield testinfra.get_host("docker://" + docker_id)
    subprocess.check_call(["docker", "rm", "-f", docker_id])


def test_python_version(host: Host):
    version = StrictVersion(
        host.run("python --version | awk '{print $2}'").stdout.strip()
    )
    desired_version = StrictVersion("3.11.7")
    assert version == desired_version


@pytest.mark.parametrize(
    ["package", "version"],
    [
        ("nghttp2", "1.57.0"),
        ("libssl3", "3.1.4"),
        ("libcurl", "8.5.0"),
        ("libcrypto3", "3.1.4"),
    ],
)
def test_packages_versions(host: Host, package: str, version: str):
    actual_version = StrictVersion(
        host.run(
            f"apk list | grep ^{package}"
            " | sort | head -n 1 | awk '{print $1}' | cut -d'-' -f2"
        ).stdout.strip()
    )
    desired_version = StrictVersion(version)
    assert desired_version >= actual_version


@pytest.mark.parametrize(
    ["package", "version"],
    [
        ("make", "4.4.1"),
        ("gcc", "12.2.1"),
        ("git", "2.40.1"),
        ("tar", "1.34"),
        ("xz", "5.4.3"),
    ],
)
def test_essential_utilities_versions(host: Host, package: str, version: str):
    if package in ["tar", "xz"]:
        actual_version = StrictVersion(
            host.run(
                f"{package} --version"
                " | head -n 1 | awk '{print $4}' | cut -d '_' -f 1"
            ).stdout.strip()
        )
    else:
        actual_version = StrictVersion(
            host.run(
                f"{package} --version"
                " | head -n 1 | awk '{print $3}' | cut -d '_' -f 1"
            ).stdout.strip()
        )
    desired_version = StrictVersion(version)
    assert desired_version >= actual_version


@pytest.mark.parametrize(
    ["package", "version"],
    [("pip", "23.3.1"), ("virtualenv", "20.25.0")],
)
def test_python_modules_version(host: Host, package: str, version: str):
    actual_version = StrictVersion(
        host.run(
            f"python -m {package} --version" " | head -n 1 | awk '{print $2}'"
        ).stdout.strip()
    )
    desired_version = StrictVersion(version)
    assert desired_version == actual_version
