module Jekyll
  class MyConverter < Converter
    safe true
    priority :low

    def matches(ext)
      ext =~ /^\.md|.markdown$/
    end

    def output_ext(ext)
      ".md"
    end

    def convert(content)
      content.gsub(/<img.*?alt="(.*?)".*?>/,'\0<span style="margin-top:-5px;text-decoration: underline;text-underline-offset:2px;text-decoration-color:#d9d9d9;font-size:13px;text-align:center;display:block;">\1</span>')
    end
  end
end
