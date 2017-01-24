require_relative 'scanner'

class Markdown < Parser
  def parse_simple_text(text)
    CGI.escape_html(text.gsub(/\s+/, " ").gsub(/^\s+$/, ""))
  end
  def parse_raw_text(text, tag)
    text
  end
  class ParseState
    attr_accessor :infos, :breadcrumbs, :preprocessors, :postprocessors
    def preprocs(element:, tag:, text:)
      @preprocessors.each do |meth|
        meth[element: element, tag: tag, state: self, text: text]
      end
    end
    def postprocs(element:, tag:, text:)
      @postprocessors.each do |meth|
        puts "Method : #{meth.inspect}"
        meth[element: element, tag: tag, state: self, text: text]
      end
    end
    def initialize
      @infos = {}
      @breadcrumbs = []
      @preprocessors = []
      @postprocessors = []
    end

    @@swapper_procs_meths = {
      preprocs: :preprocessors,
      postprocs: :postprocessors
    }
    def push_swapper_procs(swapper)
      @@swapper_procs_meths.each do |meth_name, self_meth|
        var = swapper.send(meth_name)
        if (var && var.kind_of?(Array))
	  self.send(self_meth).push(*var)
	end
      end
    end
     
    def pop_swapper_procs(swapper)
      @@swapper_procs_meths.each do |meth_name, self_meth|
        var = swapper.send(meth_name)
        if (var && var.kind_of?(Array))
	  self.send(self_meth).pop(var.length)
	end
      end
    end
  end

  class Swapper
    
    attr_reader :preprocs, :postprocs
    def initialize(open:, content:, close:, 
                  preprocs: nil, postprocs: nil)
      @open     = open
      @content  = content
      @close    = close
      @preprocs = preprocs
      @postprocs = postprocs
      @procs_meths = {
        preprocessors:  preprocs,
	postprocessors: postprocs
      }
    end

    @@replacer = {}
    @@replacer.default = ""
    def parsed_text(tag:, state:, content:, swap_infos:)
      text = ""
      case swap_infos
        when Array
          swap_infos.each do |meth|
            meth[tag: tag, state: state, content: content, 
                 text: text, replacements: @@replacer]
          end
        when String
          text = swap_infos
      end
      
      @@replacer.clear
      @@replacer.merge!(state.infos)
      @@replacer.merge!(tag.attributes)
      @@replacer[:content] = content
      # puts "replacer for #{tag.name} : #{@@replacer.inspect}"
      (text % @@replacer)
    end
    def open(tag:, state:, content: nil)
      result = parsed_text(
        tag: tag, state: state, content: content, swap_infos: @open
      )
      result
    end
    def close(tag:, state:, content: nil)
      result = parsed_text(
        tag: tag, state: state, content: content, swap_infos: @close
      )
      result
    end
    def content(tag:, state:, content:)
      result = parsed_text(
        tag: tag, state: state, content: content, swap_infos: @content
      )
      result
    end
  end

 def self.list_item_done(**args)
    state = args[:state].infos
    if state[:listtype] == :numeric
      listmark = state[:listmark]
      state[:listmark] = listmark.next
    end
  end

  def self.push_list_state(**args)
    state = args[:state].infos
    tag   = args[:tag]
    state[:list_types]  ||= []
    state[:list_marks] ||= []
    state[:indent]     ||= 0

    list_indent = state[:indent].next
    list_type = (tag.attributes[:type] || :simple)
    list_mark = '*'
    list_mark = '1' if list_type == :numeric
    listindent = " " * list_indent

    state[:list_types].push(list_type)
    state[:listtype] = list_type
    state[:list_marks].push(list_mark)
    state[:listmark] = list_mark
    state[:indent]   = list_indent
  end

  def self.pop_list_state(**args)
    state = args[:state].infos
    state[:listtype] = state[:list_types].pop
    state[:listmark] = state[:list_marks].pop
    state[:indent]   = state[:indent].pred
  end

  # TODO : Avoid writing directly to the text at all costs !
  #        Instead, return multiple text additions that will
  #        be concatenated and added by the main thread.
  def self.table_header_end(**args)
    args[:text] << "-|" * args[:state].infos[:table_rows] << "\n"
  end

  def self.start_table_rows_counter(**args)
    args[:state].infos[:table_rows] = 0
  end

  def self.count_table_rows(**args)
    tag = args[:tag]
    if (tag.name == :th && tag.close?)
      puts "+ 1 header"
      args[:state].infos[:table_rows] += 1
    end
  end
 
  @@title_blocks = [:article, :section]
  @@is_title_block = ->(tag) { @@title_blocks.include?(tag.name) }

  def self.context_title(**args)
    breadcrumbs     = args[:state].breadcrumbs
    title_blocks    = [:article, :section]
    context_block_i = breadcrumbs.rindex(&@@is_title_block)
    context_block   = breadcrumbs[context_block_i]
    sub_level       = breadcrumbs.count(&@@is_title_block)

    sub_level      += 1 if context_block.name != :article
    # TODO Avoid writing directly to the text at all costs !
    args[:text] << ("#" * sub_level) << " "
  end

  def self.Swap(open, content, close, preprocs: nil, postprocs: nil)
    Swapper.new(open: open, content: content, close: close,
                preprocs: preprocs, postprocs: postprocs)
  end
  bold = Swap("**", "%{content}", "**")  
  @@no_swap = Swap("", "", "")
  @@swaps = {
    "title": Swap([self.method(:context_title)], "%{content}", ""),
    "section:title": Swap("\n\n## ", "%{content}", ""),
    "article:title": Swap("\n\n# ", "%{content}", ""),
    h1: Swap("\n\n# ", "%{content}", ""),
    h2: Swap("\n\n## ", "%{content}", ""),
    h3: Swap("\n\n#### ", "%{content}", ""),
    h4: Swap("\n\n##### ", "%{content}", ""),
    legend: Swap("\n\n", "", ""),
    abbr: Swap("", "%{content}", ""),
    a: Swap("[", "%{content}", "](%{href})"),
    p: Swap("\n\n", "%{content}", ""),
    programlisting: Swap("\n\n```%{lang}\n", "%{content}\n", "```"),
    code: Swap("\n\n```%{lang}\n", "%{content}\n", "```"),
    output: Swap("\n\n```\n", "%{content}", "```\n"),
    note: Swap("\n\n> ", "%{content}", ""),
    list: Swap([self.method(:push_list_state)], "", 
               [self.method(:pop_list_state)]),
    item: Swap("\n%{listindent}%{listmark} ", "%{content}", 
               [self.method(:list_item_done)]),
    br: Swap("", "", "  \n"),
    register: bold,
    filename: bold,
    path: bold,
    identifier: bold,
    table: Swap("\n\n", "", ""),
    thead: Swap([self.method(:start_table_rows_counter)], "", 
                [self.method(:table_header_end)], 
                 postprocs: [self.method(:count_table_rows)]),
    tr: Swap("", "", "\n"),
    th: Swap("", "%{content}", "|"),
    td: Swap("", "%{content}", "|"),
    demonstration: Swap("\n\n    ", "%{content}", "")
  }
  @@swaps.default = @@no_swap

 
  def tag_swap(tag)
    @@swaps[tag.name]
  end

  def second_pass(splitted_content)
    result_text = ""
    parser_state = ParseState.new
    tag_swapper = @@no_swap
    current_tag = Tag.new("<///>")

    splitted_content.each do |element|
      p element
      parser_state.preprocs(
        element: element, tag: current_tag, text: result_text
      )
      case element
      when Tag
        current_tag = element
        tag_swapper = tag_swap(current_tag)
        if current_tag.open?
          parser_state.breadcrumbs.push(current_tag)
          parser_state.push_swapper_procs(tag_swapper)
          result_text << tag_swapper.open(
            tag: current_tag, state: parser_state
          )
        elsif current_tag.close?
         result_text << tag_swapper.close(
            tag: current_tag, state: parser_state
          )
	  parser_state.breadcrumbs.pop
          parser_state.pop_swapper_procs(tag_swapper)
        else tag.selfclosing?
          result_text << tag_swapper.close(
            tag: current_tag, state: parser_state
          )
        end # if current_tag.open ?
      when String
        text = element
        result_text << tag_swapper.content(
          tag: current_tag, state: parser_state, content: text
        )
      end # case element
      parser_state.postprocs(
        element: element, tag: current_tag, text: result_text
      )
    end # splitted_documents do
    result_text

  end

  def xml(text)
    second_pass(super(text))
  end
end

text = File.read("InvocTreated.xml")
prs = Markdown.new
prs.add_raw_tags(:programlisting, :code, :output)
puts prs.xml(text)

