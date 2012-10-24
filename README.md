# Loadpath Compiler
loadpath-compiler is (an admittedly janky) tool to compile the load path
for ruby applications so you can bypass Rubygems' slow file loading.

This code is not well tested, but I've been using it with Chef without
problems for a few months. 

# Using It
1. `gem install chef`
2. `ruby rbcompile.rb chef`
3. Add `~/.rbcompile/bin` to your `$PATH`

