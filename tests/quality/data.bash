#!/bin/bash

scripts=$(find commands -type f)
libs=$(find lib -name '*.sh')

success=0
failure=1
