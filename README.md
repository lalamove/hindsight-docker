# hindsight-docker
Data processing skeleton, now in docker!

# Usage
You need to volume mount the files you want to run inside hindsight, something like:
```
docker run -v ~/hindsight/run/input:/hindsight/run/input --entrypoint hindsight_cli quay.io/lalamove/hindsight:0.14.8 /hindsight/cfg/hindsight.cfg 7
```
We recommend using this image as a base image, however and as a part of your CI pipeline build in the run/load/custom_modules folder into your own image.
