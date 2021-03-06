
all: document install test

test: 
	Rscript --vanilla -e 'suppressMessages(devtools::test())'

document: man-roxygen/*
	Rscript --vanilla -e 'devtools::document()'
	
install: 
	Rscript --vanilla -e 'devtools::install()'

readme: 
	Rscript --vanilla -e 'rmarkdown::render("README.Rmd", output_format = "github_document")'
