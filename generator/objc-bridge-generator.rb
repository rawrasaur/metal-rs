#!/usr/bin/env ruby

require "active_support"
require "active_support/core_ext"
require "nokogiri"

$: << "#{__dir__}/lib"

require "bridge/output"

module Bridge
  class Node
    def initialize(node)
      if class_node_name = self.class.node
        unless class_node_name == node.name
          raise ArgumentError, "expected node name '#{class_node_name}' but got '#{node.name}'"
        end
      end

      self.prepare(node)

      children = node.children.map do |child|
        self.prepare_child(child)
      end.compact

      @children = children if children.length > 0
    end

    def children
      @children || []
    end

    def prepare_child(_)
    end

    def to_rust(_)
    end

    def self.node(value = nil)
      if value
        @node = value
      else
        @node
      end
    end
  end

  class Framework < Node
    node "framework"

    def prepare(node)
      @module = node['module']
      @no_prelude = true if node.has_attribute?('no-prelude')
    end

    def prepare_child(node)
      case node.name
      when "alias"
        Alias.new(node)
      when "class"
        Class.new(node)
      when "enumeration"
        Enumeration.new(node)
      when "extern"
        Extern.new(node)
      when "module"
        Module.new(node)
      when "protocol"
        Protocol.new(node)
      when "script"
        Script.new(node)
      when "structure"
        Structure.new(node)
      when "use"
        Use.new(node)
      end
    end

    def to_rust(o)
      o.puts("#![allow(non_upper_case_globals)]", pad: true, group: "prelude")

      unless @no_prelude
        o.puts("use std;")
        o.puts("use objc;")
        o.puts("use super::ObjectiveC;")
      end

      self.children.each { |c| c.to_rust(o) }
    end
  end

  class Protocol < Node
    node "protocol"

    attr_reader :name, :inherits

    def prepare(node)
      @name = node["name"]

      specific = node["inherits_mac"].try(:split, ",") || []
      generic = node["inherits"].try(:split, ",") || []

      @inherits = (specific + generic).map(&:strip)
    end

    def prepare_child(node)
      case node.name
      when "initializer"
        Initializer.new(node)
      when "method"
        Method.new(node)
      when "property"
        Property.new(node)
      when "script"
        Script.new(node)
      when "text"
        Text.new(node)
      end
    end

    def impl_for_self(o)
      o.block("pub fn from_ptr(ptr: *mut std::os::raw::c_void) -> Self") do |o|
        o.puts("return #{self.name}ID(ptr);")
      end
      o.puts
      o.block("pub fn from_object(obj: &mut objc::runtime::Object) -> Self") do |o|
        o.puts("return #{self.name}ID(obj as *mut objc::runtime::Object as *mut std::os::raw::c_void);")
      end
      o.puts
      o.block("pub fn nil() -> Self") do |o|
        o.puts("return #{self.name}ID(0 as *mut std::os::raw::c_void);")
      end
      o.puts
      o.block("pub fn is_nil(&self) -> bool") do |o|
        o.puts("return self.0 as usize == 0;")
      end
    end

    def to_rust(o)
      inheritance = self.inherits.length == 0 ? "ObjectiveC" : self.inherits.join(" + ")

      o.block("pub trait #{self.name} : #{inheritance}", pad: true) do |o|
        self.children.reject { |x| x.is_a?(Script) }.each { |c| c.to_rust(o) }
        self.children.select { |x| x.is_a?(Script) && x.type == "trait" }.each do |script|
          o.puts
          script.to_rust(o)
        end
      end
      o.puts
      o.puts("#[repr(C)] pub struct #{self.name}ID(*mut std::os::raw::c_void);")
      o.puts
      o.block("impl #{self.name}ID") do |o|
        self.impl_for_self(o)
        self.children.select { |x| x.is_a?(Initializer) }.each do |initializer|
          o.puts
          generics = ["T5", "T4", "T3", "T2", "T1", "T0"]

          error_argument = initializer.error_argument
          arguments = initializer.arguments(generics)

          fn_args = arguments.map { |arg| arg[0] }.compact.join(", ")
          bounds_args = arguments.map { |arg| arg[1] }.compact.join(", ")
          bounds_args = bounds_args.length > 0 ? "<#{bounds_args}>" : ""
          call_args = arguments.map { |arg| arg[3] }.compact.join(", ")

          o.block("pub fn #{initializer.name.gsub(/\Ainit/, "new")}#{bounds_args}(#{fn_args}) -> #{initializer.return_type} where Self: 'static + Sized") do |o|
            o.puts "return #{self.name}ID::alloc().#{initializer.name.underscore}(#{call_args});"
          end
        end
        self.children.select { |x| x.is_a?(Script) && x.type == "id" }.each do |script|
          o.puts
          script.to_rust(o)
        end
      end
      o.puts
      (self.inherits + [self.name]).each do |inherit|
        o.puts("impl #{inherit} for #{self.name}ID {}")
      end
      o.puts
      o.block("impl Clone for #{self.name}ID") do |o|
        o.block("fn clone(&self) -> Self") do |o|
          o.puts "let ptr = self.as_ptr();"
          o.puts
          o.puts "return Self::from_ptr(ptr).retain();"
        end
      end
      o.puts
      o.block("impl Drop for #{self.name}ID") do |o|
        o.block("fn drop(&mut self)") do |o|
          o.block("if !self.is_nil()") do |o|
            o.puts "unsafe { self.release() };"
          end
        end
      end
      o.puts
      o.block("impl ObjectiveC for #{self.name}ID") do |o|
        o.block("fn as_ptr(&self) -> *mut std::os::raw::c_void") do |o|
          o.puts("return self.0;")
        end
      end
      o.puts
      o.block("unsafe impl objc::Encode for #{self.name}ID") do |o|
        o.block("fn encode() -> objc::Encoding") do |o|
          o.puts("return unsafe { objc::Encoding::from_str(\"@\") };")
        end
      end
      o.puts
      o.block("impl std::fmt::Debug for #{self.name}ID") do |o|
        o.block("fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result") do |o|
          o.puts("return write!(f, \"{}\", self.debug_description().as_str());")
        end
      end
    end
  end

  class Class < Protocol
    node "class"

    def impl_for_self(o)
      super(o)
      o.puts
      o.block("pub fn alloc() -> Self") do |o|
        o.puts("return unsafe { msg_send![Self::class(), alloc] };")
      end
      o.puts
      o.block("pub fn class() -> &'static objc::runtime::Class") do |o|
        o.puts("return objc::runtime::Class::get(\"#{self.name}\").unwrap();")
      end
    end
  end

  class Alias < Node
    node "alias"

    attr_reader :name, :type

    def prepare(node)
      @name = node['name']
      @type = node['type']
    end

    def to_rust(o)
      o.puts("pub type #{self.name} = #{self.type};", group: "alias")
    end
  end

  class Argument < Node
    node "argument"

    attr_reader :name
    attr_reader :kind, :error, :protocol, :type

    def prepare(node)
      @name = node['name']

      if node.has_attribute?('error')
        @kind = 'error'
        @error = node['error']
      end

      if node.has_attribute?('protocol')
        raise ArgumentError, "multiple values defined" if @kind
        @kind = 'protocol'
        @protocol = node['protocol']
      end

      if node.has_attribute?('type')
        raise ArgumentError, "multiple values defined" if @kind
        @kind = 'type'
        @type = node['type']
      end
    end
  end

  class Enumeration < Node
    node "enumeration"

    attr_reader :name, :type

    def prepare(node)
      @name = node['name']
      @type = node['type']
    end

    def prepare_child(node)
      case node.name
      when "value"
        Value.new(node)
      end
    end

    def to_rust(o)
      o.block("bitflags!", pad: true) do |o|
        o.block("pub flags #{self.name}: #{self.type}") do |o|
          self.children.each { |c| c.to_rust(o) }
        end
      end
    end
  end

  class Extern < Node
    node "extern"

    attr_reader :framework

    def prepare(node)
      @framework = node['framework']
    end

    def prepare_child(node)
      case node.name
      when "function"
        Function.new(node)
      when "static"
        Static.new(node)
      end
    end

    def to_rust(o)
      o.puts("#[link(name = \"#{self.framework}\", kind = \"framework\")]", pad: true)
      if self.children.length > 0
        o.block("extern") do |o|
          self.children.each { |c| c.to_rust(o) }
        end
      else
        o.puts("extern {}")
      end
    end
  end

  class Field < Node
    attr_reader :name, :type

    def prepare(node)
      @name = node["name"]
      @type = node["type"]
      @private = node.has_attribute?('private')
    end

    def to_rust(o)
      o.puts("#{@private ? "" : "pub "}#{self.name.underscore}: #{self.type},")
    end
  end

  class Function < Node
    attr_reader :name

    def prepare(node)
      @name = node["name"]
    end

    def prepare_child(node)
      case node.name
      when "return"
        Return.new(node)
      end
    end

    def to_rust(o)
      return_values = self.children.select { |x| x.is_a? Return }.map do |return_value|
        case return_value.kind
        when "type"
          type_name = return_value.type.to_s

          " -> #{type_name}"
        else
          raise Exception, "unsupported kind #{return_value.kind}"
        end
      end

      raise ArgumentError, "too many return values" if return_values.length > 1

      return_value = return_values[0] || ""

      o.puts("fn #{self.name}()#{return_value};")
    end
  end

  class Initializer < Node
    node "initializer"

    attr_reader :selector

    def prepare(node)
      @selector = node['selector']
    end

    def prepare_child(node)
      case node.name
      when "argument"
        Argument.new(node)
      end
    end

    def arguments(generics)
      self.children.select { |x| x.is_a?(Argument) }.map do |argument|
        g = generics.pop

        case argument.kind
        when "error"
          [nil, nil, "&mut #{argument.name.underscore}", nil]
        when "protocol"
          ["#{argument.name.underscore}: &#{g}", "#{g}: 'static + #{argument.protocol}", "#{argument.name.underscore}.as_ptr()", argument.name.underscore]
        when "type"
          ["#{argument.name.underscore}: #{argument.type}", nil, "#{argument.name.underscore}", argument.name.underscore]
        else
          raise Exception, "unknown kind #{argument.kind}"
        end
      end
    end
    
    def error_argument
      error_arguments = self.children.select { |x| x.is_a?(Argument) && x.kind == "error" }
      raise ArgumentError, "multiple error arguments" if error_arguments.count > 1

      error_arguments.first
    end

    def name
      self.selector.gsub(/:\z/, "").tr(":", "_").underscore
    end

    def return_type
      if self.error_argument
        "Result<Self, #{error_argument.error}ID>"
      else
        "Self"
      end
    end

    def to_rust(o)
      generics = ["T5", "T4", "T3", "T2", "T1", "T0"]

      error_argument = self.error_argument
      arguments = self.arguments(generics)

      fn_args = (["self"] + arguments.map { |arg| arg[0] }).compact.join(", ")
      msg_args = arguments.map { |arg| arg[2] }
      msg_args = "(#{msg_args.length == 1 ? "#{msg_args[0]}," : msg_args.join(", ")})"
      bounds_args = arguments.map { |arg| arg[1] }.compact.join(", ")
      bounds_args = bounds_args.length > 0 ? "<#{bounds_args}>" : ""

      return_value_string = " -> #{return_type}"

      o.block("fn #{self.name}#{bounds_args}(#{fn_args})#{return_value_string} where Self: 'static + Sized", pad: true) do |o|
        if error_argument
          o.puts("let mut #{error_argument.name} = #{error_argument.error}ID::nil();")
          o.puts
        end

        o.block("unsafe") do |o|
          o.block("match objc::__send_message(self.as_object(), sel!(#{self.selector}), #{msg_args})") do |o|
            o.puts("Err(s) => panic!(\"{}\", s),")
            o.block("Ok(result) =>") do |o|
              if error_argument
                o.puts("std::mem::forget(self);")
                o.puts
                o.block("if !#{error_argument.name}.is_nil()") do |o|
                  o.puts("return Err(#{error_argument.name})")
                end
                o.puts
                o.puts("return Ok(result);")
              else
                o.puts("std::mem::forget(self);")
                o.puts
                o.puts("return result;")
              end
            end
          end
        end
      end
    end
  end

  class Method < Node
    node "method"

    attr_reader :selector

    def prepare(node)
      @selector = node['selector']
    end

    def prepare_child(node)
      case node.name
      when "argument"
        Argument.new(node)
      when "return"
        Return.new(node)
      end
    end

    def name
      self.selector.gsub(/:\z/, "").tr(":", "_").underscore
    end

    def to_rust(o)
      generics = ["T5", "T4", "T3", "T2", "T1", "T0"]

      error_arguments = self.children.select { |x| x.is_a?(Argument) && x.kind == "error" }
      raise ArgumentError, "multiple error arguments" if error_arguments.count > 1
      error_argument = error_arguments.first

      arguments = self.children.select { |x| x.is_a?(Argument) }.map do |argument|
        case argument.kind
        when "error"
          [nil, nil, "&mut #{argument.name.underscore}"]
        when "protocol"
          g = generics.pop

          raise Exception, "ran out of generics" unless g

          ["#{argument.name.underscore}: &#{g}", "#{g}: 'static + #{argument.protocol}", "#{argument.name.underscore}.as_ptr()"]
        when "type"
          ["#{argument.name.underscore}: #{argument.type}", nil, "#{argument.name.underscore}"]
        else
          raise Exception, "unknown kind #{argument.kind}"
        end
      end

      owned = self.selector.match(/\A(alloc|new|copy|mutableCopy)/)

      return_values = self.children.select { |x| x.is_a? Return }.map do |return_value|
        case return_value.kind
        when "protocol"
          id_name = "#{return_value.protocol}ID"

          [id_name, nil, owned ? "result" : "result.retain()"]
        when "type"
          type_name = return_value.type.to_s

          [type_name, nil, "result"]
        when "generic"
          g = generics.pop

          raise Exception, "ran out of generics" unless g

          [g, "#{g}: 'static + #{return_value.generic}", owned ? "result" : "result.retain()"]
        else
          raise Exception, "unknown kind #{return_value.kind}"
        end
      end

      raise ArgumentError, "too many return values" if return_values.length > 1

      fn_args = (["&self"] + arguments.map { |arg| arg[0] }).compact.join(", ")
      msg_args = arguments.map { |arg| arg[2] }
      msg_args = "(#{msg_args.length == 1 ? "#{msg_args[0]}," : msg_args.join(", ")})"
      return_value = return_values[0] || ["()", nil, "result"]
      bounds_args = (arguments.map { |arg| arg[1] } + [return_value[1]]).compact.join(", ")
      bounds_args = bounds_args.length > 0 ? "<#{bounds_args}>" : ""

      return_value_string = if error_argument
        " -> Result<#{return_value[0]}, #{error_argument.error}ID>"
      else
         return_value[0] == "()" ? "" : " -> #{return_value[0]}"
      end

      o.block("fn #{self.name}#{bounds_args}(#{fn_args})#{return_value_string} where Self: 'static + Sized", pad: true) do |o|
        if error_argument
          o.puts("let mut #{error_argument.name} = #{error_argument.error}ID::nil();")
          o.puts
        end

        o.block("unsafe") do |o|
          o.block("match objc::__send_message(self.as_object(), sel!(#{self.selector}), #{msg_args})") do |o|
            o.puts("Err(s) => panic!(\"{}\", s),")
            o.block("Ok(r) =>") do |o|
              if error_argument
                o.block("if !#{error_argument.name}.is_nil()") do |o|
                  o.puts("return Err(#{error_argument.name})")
                end
                o.puts
                o.puts("let result: #{return_value[0]} = r;")
                o.puts
                o.puts("return Ok(#{return_value[2]});")
              else
                o.puts("let result: #{return_value[0]} = r;")
                o.puts
                o.puts("return #{return_value[2]};")
              end
            end
          end
        end
      end
    end
  end

  class Module < Node
    attr_reader :name

    def prepare(node)
      @name = node["name"]
      @private = node.has_attribute?('private')
    end

    def to_rust(o)
      o.puts("#{@private ? "" : "pub "}mod #{self.name.underscore};")
    end
  end

  class Property < Node
    node "property"

    attr_reader :name
    attr_reader :kind, :protocol, :type
    attr_reader :getter, :setter

    def read_only?
      @read_only
    end

    def weak?
      @weak
    end

    def prepare(node)
      @name = node['name']

      if node.has_attribute?('protocol')
        @kind = 'protocol'
        @protocol = node['protocol']
      end

      if node.has_attribute?('type')
        raise ArgumentError, "multiple values defined" if @kind
        @kind = 'type'
        @type = node['type']
      end

      raise ArgumentError, "no value defined" unless @kind

      @read_only = node.has_attribute?('read-only')
      @weak = node.has_attribute?('weak')

      @getter = node['getter'] || @name
      @setter = node['setter'] || "set#{@name.upcase_first}"

    end

    def to_rust(o)
      case self.kind
      when "type"
        o.block("fn #{self.getter.underscore}(&self) -> #{self.type} where Self: 'static + Sized", pad: true) do |o|
          o.block("unsafe") do |o|
            o.puts("let target = self.as_object();")
            o.puts
            o.block("return match objc::__send_message(target, sel!(#{self.getter}), ())") do |o|
              o.puts("Err(s) => panic!(\"{}\", s),")
              o.puts("Ok(r) => r")
            end
          end
        end
        unless self.read_only?
          o.puts
          o.block("fn #{self.setter.underscore}(&self, #{self.name.underscore}: #{self.type}) where Self: 'static + Sized") do |o|
            o.block("unsafe") do |o|
              o.puts("let target = self.as_object();")
              o.puts
              o.block("return match objc::__send_message(target, sel!(#{self.setter}:), (#{self.name.underscore},))") do |o|
                o.puts("Err(s) => panic!(\"{}\", s),")
                o.puts("Ok(()) => ()")
              end
            end
          end
        end
      when "protocol"
        id_name = "#{self.protocol}ID"

        o.block("fn #{self.getter.underscore}(&self) -> #{id_name} where Self: 'static + Sized", pad: true) do |o|
          o.block("unsafe") do |o|
            o.puts("let target = self.as_object();")
            o.puts
            o.block("match objc::__send_message(target, sel!(#{self.getter}), ())") do |o|
              o.puts("Err(s) => panic!(\"{}\", s),")
              o.block("Ok(r) =>") do |o|
                o.puts("let r: #{id_name} = r;")
                o.puts
                o.puts("return r.retain();")
              end
            end
          end
        end
        unless self.read_only?
          o.puts
          o.block("fn #{self.setter.underscore}<T: 'static + ObjectiveC + #{self.protocol}>(&self, #{self.name.underscore}: &T) where Self: 'static + Sized") do |o|
            o.block("unsafe") do |o|
              o.puts("let target = self.as_object();")
              o.puts
              o.block("return match objc::__send_message(target, sel!(#{self.setter}:), (#{self.name.underscore}.as_ptr(),))") do |o|
                o.puts("Err(s) => panic!(\"{}\", s),")
                o.puts("Ok(()) => ()")
              end
            end
          end
        end
      else
        raise Exception, "unknown kind #{self.kind}"
      end
    end
  end

  class Return < Node
    node "return"

    attr_reader :kind, :protocol, :type, :generic

    def prepare(node)
      if node.has_attribute?('protocol')
        @kind = 'protocol'
        @protocol = node['protocol']
      end

      if node.has_attribute?('type')
        raise ArgumentError, "multiple values defined" if @kind
        @kind = 'type'
        @type = node['type']
      end

      if node.has_attribute?('generic')
        raise ArgumentError, "multiple values defined" if @kind
        @kind = 'generic'
        @generic = node['generic']
      end

      raise ArgumentError, "no value defined" unless @kind
    end
  end

  class Script < Node
    node "script"

    attr_reader :type, :content

    def prepare(node)
      @type = node['type']
      @content = node.text.strip
    end

    def to_rust(o)
      @content.lines.each { |line| o.puts(line) }
    end
  end

  class Static < Node
    attr_reader :name
    attr_reader :kind, :protocol, :type

    def prepare(node)
      @name = node["name"]
      @public = node.has_attribute?('public')
      
      if node.has_attribute?('protocol')
        @kind = 'protocol'
        @protocol = node['protocol']
      end

      if node.has_attribute?('type')
        raise ArgumentError, "multiple values defined" if @kind
        @kind = 'type'
        @type = node['type']
      end
    end

    def to_rust(o)
      case self.kind
      when "type"
        o.puts("#{@public ? "pub " : ""}static #{self.name}: #{self.type};", group: "static")
      when "protocol"
        o.puts("#{@public ? "pub " : ""}static #{self.name}: #{self.protocol}ID;", group: "static")
      else
        raise ArgumentError, "invalid kind #{self.kind}"
      end
    end
  end

  class Structure < Node
    node "structure"

    attr_reader :name

    def prepare(node)
      @name = node['name']
    end

    def prepare_child(node)
      case node.name
      when "field"
        Field.new(node)
      end
    end

    def to_rust(o)
      o.puts("#[repr(C)]", pad: true, group: "structure")
      o.puts("#[derive(Clone, Copy, Debug)]")
      o.block("pub struct #{self.name}") do |o|
        self.children.each { |c| c.to_rust(o) }
      end
    end
  end

  class Use < Node
    attr_reader :use

    def prepare(node)
      @use = node.text
      @private = !node.has_attribute?('public')
    end

    def to_rust(o)
      o.puts("#{@private ? "" : "pub "}use #{self.use};", group: "use")
    end
  end

  class Value < Node
    attr_reader :name, :value

    def prepare(node)
      @name = node["name"]
      @value = node["value"]
    end

    def to_rust(o)
      o.puts("const #{self.name} = #{self.value},")
    end
  end

  class Text < Node
    def prepare(node)
      @node = node
    end
  end

  def self.generate(from, output)
    xml = Nokogiri::HTML.fragment(from).child

    Bridge::Framework.new(xml).to_rust(output)
  end
end

if $0 == __FILE__
  Bridge.generate(File.read(ARGV[0]), Bridge::Output.new(STDOUT))
end