#!/usr/bin/env python

# Test whether a valid CONNECT results in the correct CONNACK packet using an SSL connection.

import socket
import ssl
import sys
import time

if sys.version < '2.7':
    print("WARNING: SSL not supported on Python 2.6")
    exit(0)

import inspect, os, sys
# From http://stackoverflow.com/questions/279237/python-import-a-module-from-a-folder
cmd_subfolder = os.path.realpath(os.path.abspath(os.path.join(os.path.split(inspect.getfile( inspect.currentframe() ))[0],"..")))
if cmd_subfolder not in sys.path:
    sys.path.insert(0, cmd_subfolder)

import mosq_test
import emqttd

rc = 1
keepalive = 10
connect_packet = mosq_test.gen_connect("connect-success-test", keepalive=keepalive)
connack_packet = mosq_test.gen_connack(rc=0)

emqttd.start('08-ssl-connect-no-auth-wrong-ca.conf')

time.sleep(0.5)

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
ssock = ssl.wrap_socket(sock, ca_certs="../ssl/test-alt-ca.crt", cert_reqs=ssl.CERT_REQUIRED)
ssock.settimeout(20)
try:
    ssock.connect(("localhost", 1888))
except ssl.SSLError as err:
    if err.errno == 1:
        rc = 0
finally:
    ssock.close()

emqttd.stop()
exit(rc)
