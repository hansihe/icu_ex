#!/bin/bash
set -xe

# cargo install --git https://github.com/unicode-org/icu4x.git --rev b6791e78b1c2f69ffaeb5f60c53f6bceebf7e32a --features experimental icu4x-datagen

rm -r data
icu4x-datagen --markers all --locales modern --format baked --pretty --out data
