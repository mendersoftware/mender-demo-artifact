#!/usr/bin/python3
# Copyright 2022 Northern.tech AS
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        https://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

import pytest
import time
import os.path
import requests

from mender_test_containers.helpers import *

# The tests in this class need to be run in order.
@pytest.mark.usefixtures("setup_mender_configured")
class TestDemoArtifact():
    def check_valid_page(self, setup_test_container, setup_tester_ssh_connection, expect_fail=False):
        attempts = 10
        while True:
            try:
                with PortForward(setup_tester_ssh_connection, setup_test_container.key_filename, 8880, 85):
                    response = requests.get("http://localhost:8880/", timeout=10)
                    assert "Congratulations" in response.text
                    break
            except Exception as e:
                if expect_fail:
                    return

                try:
                    print(setup_tester_ssh_connection.sudo("journalctl -u mender-demo-artifact | tail -n 50", warn=True).stdout)
                except Exception as ex:
                    print("Unable to run commands")
                    print(ex)
                print(e)
                # Sometimes the host can be slow to bring up the port.
                attempts -= 1
                if attempts <= 0:
                    raise
                time.sleep(10)
                continue

    def test_fail_to_install_demo_artifact(self, setup_test_container, setup_tester_ssh_connection):
        setup_tester_ssh_connection.sudo("rm -rf /data/www/localhost")
        try:
            setup_tester_ssh_connection.sudo("mkdir -p /data/www")
            # Put a file in the way which blocks the package.
            setup_tester_ssh_connection.run("echo test_content | sudo tee /data/www/localhost")

            put(setup_tester_ssh_connection, "../output/mender-demo-artifact.mender",
                key_filename=setup_test_container.key_filename)
            output = setup_tester_ssh_connection.sudo("mender-update install mender-demo-artifact.mender", warn=True)
            assert output.exited != 0
            setup_tester_ssh_connection.run("! test -f /etc/init.d/mender-demo-artifact")
            setup_tester_ssh_connection.run("! test -f /etc/rc3.d/S99mender-demo-artifact")
            output = setup_tester_ssh_connection.run("cat /data/www/localhost")
            assert output.stdout.strip() == "test_content"

        finally:
            setup_tester_ssh_connection.sudo("rm -rf /data/www/localhost")

    def test_install_demo_artifact(self, setup_test_container, setup_tester_ssh_connection):
        put(setup_tester_ssh_connection, "../output/mender-demo-artifact.mender",
            key_filename=setup_test_container.key_filename)
        output = setup_tester_ssh_connection.sudo("mender-update install mender-demo-artifact.mender")

        self.check_valid_page(setup_test_container, setup_tester_ssh_connection)

    def test_reboot_demo_still_running(self, setup_test_container, setup_tester_ssh_connection):
        try:
            setup_tester_ssh_connection.sudo("reboot")
        except:
            # Often happens if we disconnect as a result of the reboot.
            pass

        # Give the reboot time to commence.
        time.sleep(10)

        # Recheck condition from first test.
        self.check_valid_page(setup_test_container, setup_tester_ssh_connection)

    def test_rollback_demo_artifact(self, setup_test_container, setup_tester_ssh_connection):
        setup_tester_ssh_connection.sudo("mender-update rollback")
        setup_tester_ssh_connection.run("! test -f /etc/init.d/mender-demo-artifact")
        setup_tester_ssh_connection.run("! test -f /etc/rc3.d/S99mender-demo-artifact")
        self.check_valid_page(setup_test_container, setup_tester_ssh_connection, expect_fail=True)
