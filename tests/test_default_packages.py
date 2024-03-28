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

@pytest.mark.parametrize(
    ["package", "command", "version"],
    [
        ("go", "go version", "1.22.1"),
        ("python", "python --version", "3.12"),
    ],
    ids=["go-1.22.1", "python-3.12"]
)
def test_packages_versions(host: Host, package: str, command: str, version: str):
    output = host.run(command).stdout.strip()
    assert version in output

@pytest.mark.parametrize(
    ["package", "version"],
    [("pip", "23.2")],
)
def test_python_modules_version(host: Host, package: str, version: str):
    actual_version = StrictVersion(
        host.run(
            f"python -m {package} --version" " | head -n 1 | awk '{print $2}'"
        ).stdout.strip()
    )
    desired_version = StrictVersion(version)
    assert desired_version == actual_version
