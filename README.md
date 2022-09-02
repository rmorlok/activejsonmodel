# Active JSON Model

[![Gem Version](https://badge.fury.io/rb/activejsonmodel.svg)](https://rubygems.org/gems/activejsonmodel)
![Github Actions CI](https://github.com/rmorlok/activejsonmodel/actions/workflows/ci.yaml/badge.svg)

A library for creating Active Models that can serialize/deserialize to JSON. This includes full support for validation
and change detection through nested models.

Active JSON Model can optionally be combined with Active Record to create nested child models via JSON/JSONB columns. 

---

- [Quick start](#quick-start)
- [Gem on RubyGems](https://rubygems.org/gems/activejsonmodel)
- [Support](#support)
- [License](#license)
- [Code of conduct](#code-of-conduct)
- [Contribution guide](#contribution-guide)

## Quick start

Install the gem:

```
$ gem install activejsonmodel
```

If not using in an auto-loading context (i.e. Rails), import it:

```ruby
require "active_json_model"
```

define a model:

```ruby
class Point
  include ActiveJsonModel::Model
  
  json_attribute :x, Integer
  json_attribute :y, Integer
end
```

create an instance of a model:

```ruby
origin = Point.new(x: 0, y:0)
# => #<Point:0x00007f9f0d0e6538 @mutations_before_last_save=nil, @mutations_from_database=nil, @x=0, @x_is_default=false, @y=0, @y_is_default=false>
```

export it to a JSON-like hash:

```ruby
data = origin.dump_to_json
# => {:x=>0, :y=>0}
```

encode it as JSON:

```ruby
JSON.dump(origin.dump_to_json)
# => "{\"x\":0,\"y\":0}"
```

load data from a hash object:

```ruby
point2 = Point.load({x: 17, y:42})
# => #<Point:0x00007f9f0d10d5c0 @_active_json_model_loaded=true, @mutations_before_last_save=nil, @mutations_from_database=nil, @x=17, @x_is_default=false, @y=42, @y_is_default=false>
```

load from a raw JSON string:

```ruby
point3 = Point.load("{\"x\":12,\"y\":19}")
# => #<Point:0x00007fe9c0113c88 @_active_json_model_loaded=true, @mutations_before_last_save=nil, @mutations_from_database=nil, @x=12, @x_is_default=false, @y=19, @y_is_default=false>
```

nest models:

```ruby
class Rectangle
  include ActiveJsonModel::Model

  json_attribute :top_left, Point
  json_attribute :bottom_right, Point
  
  def contains(point)
    point.x >= top_left.x && 
      point.x <= bottom_right.x &&
      point.y <= top_left.y &&
      point.y >= bottom_right.y
  end
end
```

If you are using Active Record, use the model as an attribute:

```ruby
# db/migrate/20220101000001_create_image_annotations.rb
class CreateImageAnnotations < ActiveRecord::Migration[7.0]
  def change
    create_table :image_annotations do |t|
      t.jsonb      :region_of_interest, null: false, default: {}
      t.string     :note, null: false, default: ''
    end
  end
end

# app/models/image_annotation.rb
class ImageAnnotation < ActiveRecord::Base 
  attribute :region_of_interest, Rectangle.attribute_type
end

# use...
rect = Rectangle.new(
  top_left: Point.new(x: 10, y: 100),
  bottom_right: Point.new(x: 110, y: 0)
)
ia = ImageAnnotation.new(region_of_interest: rect, note: "Check out this mistake")
ia.save
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

### Building Gem Locally

Build the gem to `pkg/activejsonmodel-x.x.x.gem`:

```bash
rake build
```

Install the gem locally and import it:

```bash
$ gem install ./pkg/activejsonmodel-x.x.x.gem
Successfully installed activejsonmodel-x.x.x
Parsing documentation for activejsonmodel-x.x.x
Installing ri documentation for activejsonmodel-x.x.x
Done installing documentation for activejsonmodel after 0 seconds
1 gem installed

$ irb
irb(main):001:0> require 'active_json_model'
=> true 
```

### Releasing a new version

1. Update `lib/activejsonmodel/version.rb`

```ruby
module ActiveJsonModel
  VERSION = "x.x.x".freeze
end
```

2. Commit all changes
3. Release the changes using rake:

```bash
$ rake release
active_json_model x.x.x built to pkg/active_json_model-x.x.x.gem.
Tagged vx.x.x.
Pushed git commits and release tag.
Pushing gem to https://rubygems.org...
Successfully registered gem: active_json_model (x.x.x)
Pushed active_json_model x.x.x to rubygems.org
Don't forget to publish the release on GitHub!
```

Note that this pushes changes to github and creates a draft release on github. 