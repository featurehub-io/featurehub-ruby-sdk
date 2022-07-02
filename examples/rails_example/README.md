# Rails Example

This is an example Rails app that uses the FeatureHub Ruby SDK. Find below a (hopefully) comprehensive list of steps
that were use to generate this application as well as a walkthrough of the important bits of code to take a look at in
order to understand how to use the FeatureHub Ruby SDK in your Rails app(s)!

## Requirements

This is a mostly standard Rails app. There are a couple of minor bells and whistles that shouldn't be uncomfortable for
most folks.

It's reasonably common to work with multiple versions of Ruby on a single machine, and you'll notice that this app has a
`.ruby-version` file. If you have [rbenv](https://github.com/rbenv/rbenv) installed then you can run `rbenv install`
from the base directory of this project to (1) install Ruby 3.1.2 on your machine and (2) use it as the ruby version for
this project.

After making sure the correct version of Ruby is installed, you can install all the dependencies for the project by
running `bundle install`.

## Important bits of code

To use the FeatureHub Ruby SDK in your Rails app, you need to install it first! Check out the [Gemfile](Gemfile#L7) to
see how you can install the gem in your Rails app.


