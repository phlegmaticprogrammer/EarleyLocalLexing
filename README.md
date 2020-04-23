# EarleyLocalLexing  ![](https://github.com/phlegmaticprogrammer/EarleyLocalLexing/workflows/macOS/badge.svg)  ![](https://github.com/phlegmaticprogrammer/EarleyLocalLexing/workflows/Linux/badge.svg) 

Copyright (c) 2020 Steven Obua

License: MIT License

---

This is an implementation of *parameterized local lexing*. It is an extension of Earley's parsing algorithm. 

The focus of this implementation is to be simple and correct, and thus to be able to serve as a reference implementation.

This package is not meant to be used *directly* for parsing, it is a library that other tools providing more convenient user interfaces can build upon. [Nevertheless, the API of this package is fully documented](https://phlegmaticprogrammer.github.io/EarleyLocalLexing). A good starting point to understand it is the documentation for `Grammar`.

Background information on (parameterized) local lexing can be found in these two papers:

- [**Local Lexing** — *Steven Obua*, *Phil Scott*, *Jacques Fleuriot*](https://arxiv.org/abs/1702.03277)
- [**Parameterized Local Lexing** — *Steven Obua*](https://arxiv.org/abs/1704.04215)

There exists also a [formal correctness proof in Isabelle](https://www.isa-afp.org/entries/LocalLexing.html) of the (unparameterized) local lexing algorithm.
