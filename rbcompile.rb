require 'pp'
require 'fileutils'
require 'rubygems'

# ==HAX WARNINGS:
# * this does some terrible things, like using a regex to prevent rubygems from
#   loading at all. This will be made non-terrible in the future.
# * Dependency resolution is amateur hour. This will also be made non terrible
#   in the future.
# ==Philosopy
# Rubygems is not bad, it's just that the design choices all favor developer
# convenince over performance. I use those features to my advantage all the
# time. However, I would like my command line applications to run quickly.
# ==Usage
#     mkdir -p ~/.rbcompile/apps/chef
#     mkdir -p ~/.rbcompile/bin
#
#     ruby rbcompile.rb
#
#     add ~/.rbcompile/bin to your $PATH
#
# ==Results
# * with:
#     knife -h > /dev/null  0.47s user 0.07s system 93% cpu 0.569 total
# * without:
#     knife -h > /dev/null  2.63s user 0.17s system 97% cpu 2.869 total
#

class RbCompile

  # For the rough cut, I'm ignoring all of the thorny version requirement
  # conflict possibilities, and naming my exception class accordingly.
  class AmateurHour < RuntimeError
  end

  class DepCompiler
    def initialize(gem_name)
      @gem_name = gem_name
      @primary_gemspec = nil
      @all_specs = []
    end

    def gemspecs
      expand_deps(primary_gem)
      @all_specs
    end

    def primary_gem
      @primary_gem ||= Gem::Specification.find_by_name(@gem_name)
    end


    def expand_deps(gemspec)
      # TODO: this is nieve, and bundler and rubygems both have solutions for this.
      # pick one and use it.
      @all_specs << gemspec
      gemspec.runtime_dependencies.each do |runtime_dep|
        spec = Gem::Specification.find_by_name(runtime_dep.name, *runtime_dep.requirements_list)
        next if @all_specs.include?(spec)
        if conflicting = @all_specs.find {|s| s.name == spec.name }
          raise AmateurHour, "My nieve implementation has been foiled by conflicting deps: #{spec.name} versions #{conflicting.version}, #{spec.version}"
        end
        expand_deps(spec)
      end
    end
  end

  def self.gen_loader(dep_paths)
    <<-LOADER
module Kernel
  RUBYGEMS = /^rubygems/

  alias :rbcompile_orignal_require :require

  def require(path)
    return false if path =~ RUBYGEMS
    rbcompile_orignal_require(path)
  end
end

COMPILED_PATHS =[
#{dep_paths.map {|p| "\"#{p}\""}.join(",\n")}
]


$:.concat(COMPILED_PATHS)
LOADER
  end


  def self.gen_binary(name, load_path, dep_paths)
    <<-BINFILE
#!#{Gem.ruby}

#{gen_loader(dep_paths)}

load "#{load_path}"
BINFILE
  end

  def self.run(gem_name)
    compiler = DepCompiler.new(gem_name)
    gems_to_link = compiler.gemspecs
    gem_dest_root = File.expand_path("~/.rbcompile/apps/#{gem_name}")
    FileUtils.mkdir_p(gem_dest_root)
    gems_to_link.each do |gemspec|
      puts "ln -sf #{gemspec.full_gem_path} #{gem_dest_root}/#{gemspec.full_name}"
      FileUtils.ln_sf(gemspec.full_gem_path, "#{gem_dest_root}/#{gemspec.full_name}")
    end

    require_paths = gems_to_link.map {|g| g.require_paths.map {|p| "#{gem_dest_root}/#{g.full_name}/#{p}"}}.flatten

    File.open(File.expand_path("~/.rbcompile/apps/#{gem_name}/load.rb"), "w", 0644) do |f|
      f.puts gen_loader(require_paths)
    end

    compiler.primary_gem.executables.each do |ex|
      executable_dest = File.expand_path("~/.rbcompile/apps/#{gem_name}/#{compiler.primary_gem.full_name}/bin/#{ex}")
      File.open(File.expand_path("~/.rbcompile/bin/#{ex}"), "w", 0755) do |f|
        f.puts gen_binary(ex, executable_dest, require_paths)
      end
      puts "generated #{executable_dest}"
    end

  end

end

RbCompile.run(ARGV[0])
