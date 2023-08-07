#!/bin/bash

if [ -d "data" ]; then
	find "data" -type f -print;
	find "data" -type f -delete;
fi;
