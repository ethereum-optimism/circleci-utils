#!/bin/bash
FILE_PATH=$(dirname $0)
cd $FILE_PATH/src

circleci orb validate @orb.yml
