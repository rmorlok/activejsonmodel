# activejsonmodel

[![Gem Version](https://badge.fury.io/rb/activejsonmodel.svg)](https://rubygems.org/gems/activejsonmodel)
[![Circle](https://circleci.com/gh/rmorlok/activejsonmodel/tree/main.svg?style=shield)](https://app.circleci.com/pipelines/github/rmorlok/activejsonmodel?branch=main)
[![Code Climate](https://codeclimate.com/github/rmorlok/activejsonmodel/badges/gpa.svg)](https://codeclimate.com/github/rmorlok/activejsonmodel)

TODO: Description of this gem goes here.

---

- [Quick start](#quick-start)
- [Support](#support)
- [License](#license)
- [Code of conduct](#code-of-conduct)
- [Contribution guide](#contribution-guide)

## Quick start

```
$ gem install activejsonmodel
```

```ruby
require "active_json_model"
```

## Support

If you want to report a bug, or have ideas, feedback or questions about the gem, [let me know via GitHub issues](https://github.com/rmorlok/activejsonmodel/issues/new) and I will do my best to provide a helpful answer. Happy hacking!

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Code of conduct

Everyone interacting in this project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Contribution guide

Pull requests are welcome!

### Development Setup

```bash
brew install rbenv
```

Add the following to `~/.zshrc`:

```bash
RBENV=`which rbenv`
if [ $RBENV ] ; then
  export PATH=$HOME/.rbenv/bin:$PATH
  eval "$(rbenv init -)"
fi
```

Reload the `~/.zshrc`.

Install development ruby version:

```bash
cat .ruby-version | xargs rbenv install
```

Exit and re-enter the directory to make sure the current version of ruby is used. Install dependencies:

```bash
bundle install
```

### Running Tests

Active JSON Model uses [minitest](https://github.com/minitest/minitest). To run tests, use rake:

```bash
rake test
```