# Dependabot CodeCommit Script

Dependabot script tailored for AWS CodeCommit

## Overview

Designed for use with [Dependabot-Core](https://github.com/dependabot/dependabot-core) and must be run from that project's `/bin` directory.

This project will search all (up to the first 1000) codecommit repos in a specified region and run depdendabot update actions based on the `.dependabot/config.yml` files found within.
