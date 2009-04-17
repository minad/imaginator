README
======

Imaginator is a ruby library to generate images from LaTeX/Graphviz code in a background job. This library is derived from my latex-renderer library.

Usage
-----

    Imaginator.uri = 'drbunix://tmp/imaginator.sock'
    Imaginator.dir = '/tmp/imaginator'

    Imaginator.run do |server|
      server.add_renderer(:math,  Imaginator::LaTeX.new)
      server.add_renderer(:dot,   Imaginator::Graphviz.new(:cmd => 'dot'))
      server.add_renderer(:neato, Imaginator::Graphviz.new(:cmd => 'neato'))
      server.add_renderer(:twopi, Imaginator::Graphviz.new(:cmd => 'twopi'))
      server.add_renderer(:circo, Imaginator::Graphviz.new(:cmd => 'circo'))
      server.add_renderer(:fdp,   Imaginator::Graphviz.new(:cmd => 'fdp'))
    end

    ...

    name = Imaginator.get.enqueue(:math, '1+1')
    ...
    filename = Imaginator.get.result(name)

TODO
----

* Write unit tests or specs

Authors
-------

Daniel Mendler

License
-------

This library is released under the MIT license.
