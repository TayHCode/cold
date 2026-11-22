# Contributing

This repository holds the Cold front page, `install.sh` and the docs that link the tools. Each tool's code lives in its own repository, so open issues and pull requests about a tool there.

Here, open an issue first for anything larger than a typo or a broken link. Pull requests must pass CI. To run the same checks locally:

```sh
shellcheck install.sh tests/install_test.sh
python3 -m unittest discover -s tests -v
```

The tests clone the public tools from GitHub, so they need network access.
