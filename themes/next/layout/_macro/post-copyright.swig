<ul class="post-copyright">
  <li class="post-copyright-author">
    <strong>{{ __('post.copyright.author') + __('symbol.colon') }}</strong>
    {{ post.author | default(config.author) }}
  </li>
  <li class="post-copyright-created">
    <strong>{{ __('post.copyright.created') + __('symbol.colon') }}</strong>
 {{ date(post.date, config.date_format,) }} {{ date(post.date, config.time_format,) }}
  </li>
  <li class="post-copyright-update">
    <strong>{{ __('post.copyright.modified') + __('symbol.colon') }}</strong>
 {{ date(post.updated, config.date_format,) }} {{ date(post.updated, config.time_format,) }}
  </li>
  <li class="post-copyright-link">
    <strong>{{ __('post.copyright.link') + __('symbol.colon') }}</strong>
    <a href="{{ post.url | default(post.permalink) }}" title="{{ post.title }}">{{ post.url | default(post.permalink) }}</a>
  </li>
  <li class="post-copyright-license">
    <strong>{{ __('post.copyright.license_title') + __('symbol.colon') }} </strong>
    {{ __('post.copyright.license_content', theme.post_copyright.license_url, theme.post_copyright.license) }}
  </li>
</ul>
