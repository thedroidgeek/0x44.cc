Jekyll::Hooks.register :posts, :pre_render do |post, payload|
  if Jekyll.env == "production"
    docExt = post.extname.tr('.', '')
    # only process if we deal with a markdown file
    if payload['site']['markdown_ext'].include? docExt
      newContent = post.content.gsub(/\!\[(.*)\]\(\/assets\/media\/(.+)\)/, '![\1](https://i.0x41.cf/b/\2)')
      post.content = newContent
    end
  end
end