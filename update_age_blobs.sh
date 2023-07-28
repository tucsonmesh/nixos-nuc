#!/usr/bin/env bash

tar -cz ./secrets | age --encrypt --recipient age1c68m7gantfltysged8gnt4vyvpp7un04gapt67nwjn8m7t9e6v7qchdnxd > ./secrets.tar.gz.age
