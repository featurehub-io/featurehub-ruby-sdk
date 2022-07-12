# Rails Example

This is an example Rails app that uses the FeatureHub (FH) Ruby SDK. Find below a (hopefully) comprehensive list of steps
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

## FeatureHub Setup

In order for this app to work locally you'll need to have FeatureHub set up on your machine or have an instance running somewhere.
In order to get the simplest version of FeatureHub working, run the command from [Evaluating FeatureHub](https://docs.featurehub.io/featurehub/latest/index.html#_evaluating_featurehub).

Now that FH is running, head to the Admin Console (probably running at http://localhost:8085). You'll be taken through a workflow to create a user, and then there will be some instructions on the right side of your screen.

Complete all of those steps, and when you create a feature make sure that the feature key is `demo_feature`.

## Important bits of code

To use the FeatureHub Ruby SDK in your Rails app, you need to install it first! Check out the [Gemfile](Gemfile#L7) to
see how you can install the gem in your Rails app.

Copy the [.env.example](examples/rails_example/.env.example) and rename the copy to `.env.local`. Change the API key to 
the API key that you retrieved within your local FH instance to make sure that flag evaluations occur correctly! Similarly,
you may need to update the edge URL depending on how you intend to run this app and FeatureHub.
