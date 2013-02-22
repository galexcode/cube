#!/bin/sh
aclocal && \
autoconf && \
automake
exit $?
