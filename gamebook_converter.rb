# -*- encoding: utf-8 -*-

require 'logger'

$logger = Logger.new("gbconverter.log")
$logger.level = Logger::INFO

def fatal_proc(msg)
  $stderr.puts "致命的エラー：#{msg}"
  $logger.fatal(msg)
  exit
end

def error_proc(msg)
  $stderr.puts "エラー：#{msg}"
  $logger.error(msg)
  exit
end

def warn_proc(msg)
  $stderr.puts "警告：#{msg}"
  $logger.warn(msg)
end

class TextFormatter
  def initialize
    @regexp = {
      define: %r|^\*([^:]+):([^\r\n]+)|,
      paragraph: %r|^●([^\r\n]+)|,
      fixed: %r|^●●([^\r\n]+)|,
      last: %r|^★LAST★|,
      link: %r|##([^#]+)##|,
      replace: %r|#\{{2}([^\}]+)\}{2}|
    }
  end

  def analyze(line, paragraphs, replaces)
    if @regexp[:define].match(line)
      label = $1
      str = $2
      $logger.info("got define: #{label} -> #{str}")
      replaces[label] = str
    elsif @regexp[:fixed].match(line)
      label = $1
      $logger.info("got fixed label: #{label}")
      paragraphs.add(label, true)
    elsif @regexp[:paragraph].match(line)
      label = $1
      $logger.info("got label: #{label}")
      paragraphs.add(label)
    else
      paragraphs << line
    end
  end

  def replace_last_paragraph(paragraphs)
    paragraph_names = paragraphs.paragraphs
    paragraph_names.each{|name|
      if @regexp[:last].match(name)
        label = paragraphs.last_paragraph.to_s
        $logger.info("last paragraph : #{label}")
        paragraphs.replace_paragraph_number(name, label)
        return
      end
    }
  end

  def replace_link(paragraphs)
    paragraphs.replace_link(@regexp[:link])
  end

  def replace_text(paragraphs, replaces)
    paragraphs.replace_text(replaces, @regexp[:replace])
  end

  def output(f_out, paragraphs)
    paragraphs.output{|num, bodies| f_out.puts ["●#{num}", bodies.join("")].join("\n") }
  end

  attr_reader :regexp
end

class Replaces
  def initialize
    @dict = {}
  end

  def [](key)
    @dict[key]
  end

  def []=(key, value)
    @dict[key] = value
  end

  def include?(key)
    @dict.include?(key)
  end
end

class Paragraphs
  def initialize(textformatter, first_label = 1)
    @text_formatter = textformatter
    @regexp = @text_formatter.regexp
    @first_label = first_label
    @fixed_labels = []
    @paragraphs = {}
    @label = nil
    @shuffled_labels = {}
    @reverse_shuffled_labels = {}
    @replace_labels = {}
    @count = {}
    @found_last_label = false
  end

  def [](label)
    @paragraphs[label]
  end

  def add(label, fixed_label = false)
    if @fixed_labels.include?(label) or @paragraphs.include?(label)
      error_proc("指定した先頭パラグラフのラベルはすでに存在しています : #{label}")
    elsif @paragraphs[@label] and @paragraphs[@label].empty?
      error_proc("パラグラフの本文が空です : #{label}")
    end
    @label = label
    @found_last_label = (@regexp[:last].match(label) != nil)
    if fixed_label
      @fixed_labels << @label
    elsif @fixed_labels.empty?
      error_proc("先頭のラベルは固定パラグラフでのみ指定できます : #{@label}")
    elsif @regexp[:last].match(label)
      error_proc("★LAST★ラベルは固定パラグラフでのみ指定できます : #{label}")
    end
    @paragraphs[@label] = []
  end

  def append(line)
    return unless @label
    @paragraphs[@label] << line
  end

  def <<(line)
    append(line)
  end

  def first_paragraph
    @first_label
  end

  def last_paragraph
    @first_label + @paragraphs.size - 1
  end

  def size
    @paragraphs.size
  end

  def paragraphs
    @paragraphs.keys
  end
  
  def replace_paragraph_number(old_label, new_label)
    @replace_labels[old_label] = new_label
    paragraph = @paragraphs[old_label]
    @paragraphs.delete(old_label)
    @paragraphs[new_label] = paragraph
    if @fixed_labels.include?(old_label)
      @fixed_labels.delete(old_label)
      @fixed_labels << new_label
    end
  end

  def shuffle
    labels = paragraphs
    @fixed_labels.each{|fp| labels.delete(fp) }
    (first_paragraph..last_paragraph).each{|pnum|
      pnum = pnum.to_s
      if @fixed_labels.include?(pnum)
        labels.delete(pnum)
        @shuffled_labels[pnum] = pnum
        @reverse_shuffled_labels[pnum] = pnum
      else
        nnum = labels.sample
        labels.delete(nnum)
        @shuffled_labels[pnum] = nnum
        @reverse_shuffled_labels[nnum] = pnum
      end
    }
    fatal_proc("数が連続していません\n#{paragraphs}\n#{fixed_labels}") unless labels.empty?
  end

  def replace_link(regexp)
    @paragraphs.each_key{|key|
      found = false
      @paragraphs[key].map!{|line|
        if regexp.match(line)
          base_name = $1
          num = nil
          if @replace_labels.include?(base_name)
            num = @replace_labels[base_name]
            found = true
          elsif not @reverse_shuffled_labels.include?(base_name)
            error_proc("指定したラベルが見つかりません : #{base_name}")
          else
            num = @reverse_shuffled_labels[base_name]
            found = true
          end
          line.gsub!(regexp, num)
        end
        line
      }
      warn_proc("本文中にリンクが見つかりません : #{key}") unless found
    }
  end

  def replace_text(replaces, regexp)
    @paragraphs.each_key{|key|
      @paragraphs[key].map!{|line|
        while regexp.match(line)
          base_name = $1
          value = nil
          if not replaces.include?(base_name)
            error_proc("指定した文字列の定義が見つかりません : #{base_name}")
          end
          line.gsub!(%r|#\{\{#{base_name}\}\}|, replaces[base_name])
        end
        line
      }
    }
  end

  def label_check
    warn_proc("最後のパラグラフのラベルが見つかりませんでした") unless @found_last_label
  end

  def number_check
  end

  def output
    @shuffled_labels.each_key{|key|
      yield key, @paragraphs[@shuffled_labels[key]]
    }
  end

  attr_reader :shuffled_paragraphs, :reverse_shuffled_paragraphs
end

class Paragraph
  def initalize(label, fixed_paragraph = false)
    @label = label
    @fixed_paragraph = fixed_paragraph
    @lines = []
  end

  def insert(line)
    @lines << line
  end

  def <<(line)
    insert(line)
  end

  attr_accessor :found_last_label
  attr_reader :label
end

class Converter
  def initialize(lines, textformatter)
    @lines = lines
    @text_formatter = textformatter
    @paragraphs = Paragraphs.new(textformatter)
    @replaces = Replaces.new()
  end

  def analyze
    @lines.each{|line| @text_formatter.analyze(line, @paragraphs, @replaces) }
    $logger.info("paragraphs: #{@paragraphs.size}")
    @text_formatter.replace_last_paragraph(@paragraphs)
  end

  def label_check
    @paragraphs.label_check
    $logger.info("complete!")
  end

  def shuffle
    @paragraphs.shuffle
  end

  def replace
    @text_formatter.replace_link(@paragraphs)
    @text_formatter.replace_text(@paragraphs, @replaces)
  end

  def number_check
    @paragraphs.number_check
    $logger.info("complete!")
  end

  def convert
    $logger.info("******start analyze")
    analyze
    $logger.info("******finish analyze")
    $logger.info("******start label check")
    label_check
    $logger.info("******finish label check")
    $logger.info("******start shuffle")
    shuffle
    $logger.info("******finish shuffle")
    $logger.info("******start replace")
    replace
    $logger.info("******finish replace")
    $logger.info("******start number check")
    number_check
    $logger.info("******finish number check")
  end

  def output(f_out)
    @text_formatter.output(f_out, @paragraphs)
  end
end

if __FILE__ == $0
  $logger.info("=====gamebook convert start=====")
  f_in = $stdin
  f_out = $stdout
  if ARGV.length >= 1 and ARGV[0] != "-"
    $logger.info("input: #{ARGV[0]}")
    f_in = File.open(ARGV[0], "r:UTF-8")
  else
    $logger.info("input: stdin")
  end
  if ARGV.length >= 2 and ARGV[1] != "-"
    $logger.info("output: #{ARGV[1]}")
    f_out = File.open(ARGV[1], "w:UTF-8")
  else
    $logger.info("output: stdout")
  end
  c = Converter.new(f_in.readlines, TextFormatter.new)
  $logger.info("======start convert")
  c.convert
  $logger.info("======finish convert")
  $logger.info("======start output")
  c.output(f_out)
  $logger.info("======finish output")
  $logger.info("=====gamebook convert finish=====")
end
