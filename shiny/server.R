# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
library(shiny)
library(httr)
library(jsonlite)
library(httpuv)

shinyServer(function(input, output) {

  endpoint = 'https://www.googleapis.com/genomics/v1/'

  #
  # This example gets the read bases for a sample at specific a position
  #
  google_token <- reactive({
    shiny::validate(
      need(input$clientId != '', label = 'Client ID'),
      need(input$clientSecret != '', label = 'Client secret')
    )
    app <- oauth_app('google', input$clientId, input$clientSecret)
    oauth2.0_token(oauth_endpoints('google'), app,
        scope = 'https://www.googleapis.com/auth/genomics')
  })

  # 1. First find the read group set ID for the sample
  readGroupSetId <- reactive({
    shiny::validate(
      need(input$datasetId != '', label = 'Dataset ID'),
      need(input$sample != '', label = 'Sample Name')
    )

    body <- list(datasetIds=list(input$datasetId), name=input$sample)

    res <- POST(paste(endpoint, 'readgroupsets/search', sep=''),
        query=list(fields='readGroupSets(id)'),
        body=toJSON(body, auto_unbox=TRUE), config(token=google_token()),
        add_headers('Content-Type'='application/json'))
    stop_for_status(res)

    readGroupSets <- content(res)$readGroupSets
    shiny::validate(
      need(length(readGroupSets) > 0, 'No read group sets found for that name'))

    readGroupSets[[1]]$id
  })

  # 2. Once we have the read group set ID,
  # lookup the reads at the position we are interested in
  baseCounts <- reactive({
    shiny::validate(
      need(input$chr != '', label = 'Sequence name'),
      need(input$position > 0, 'Position must be greater than 0')
    )

    body <- list(readGroupSetIds=list(readGroupSetId()),
        referenceName=input$chr, start=input$position, end=input$position + 1,
        pageSize=1024)

    res <- POST(paste(endpoint, 'reads/search', sep=''),
        query=list(fields='alignments(alignment,alignedSequence)'),
        body=toJSON(body, auto_unbox=TRUE), config(token=google_token()),
        add_headers('Content-Type'='application/json'))
    stop_for_status(res)

    reads <- content(res)$alignments
    shiny::validate(need(length(reads) > 0, 'No reads found for that position'))

    positions = sapply(lapply(lapply(reads, '[[', 'alignment'),
        '[[', 'position'), '[[', 'position')
    positions = input$position - as.integer(positions) + 1
    bases = sapply(reads, '[[', 'alignedSequence')
    bases = substr(bases, positions, positions)

    table(bases)
  })
    
  output$baseCounts <- renderUI({
    counts <- baseCounts()
    text <- list(paste(input$sample, 'bases on', input$chr, 'at',
        input$position, 'are'))
    for(base in names(counts)) {
      text <- append(text, paste(base, ':', counts[[base]]))
    }

    div(lapply(text, div))
  })


  #
  # This example gets the variants for a sample at a specific position
  #

  # 1. First find the call set ID for the sample
  callSetId <- reactive({
    shiny::validate(
      need(input$datasetId != '', label = 'Dataset ID'),
      need(input$sample != '', label = 'Sample Name')
    )

    body <- list(variantSetIds=list(input$datasetId), name=input$sample)

    res <- POST(paste(endpoint, 'callsets/search', sep=''),
        query=list(fields='callSets(id)'),
        body=toJSON(body, auto_unbox=TRUE), config(token=google_token()),
        add_headers('Content-Type'='application/json'))
    stop_for_status(res)

    callSets <- content(res)$callSets
    shiny::validate(
      need(length(callSets) > 0, 'No call sets found for that name'))

    callSets[[1]]$id
  })

  # 2. Once we have the call set ID,
  # lookup the variants that overlap the position we are interested in
  output$genotype <- renderUI({
    shiny::validate(
      need(input$chr != '', label = 'Sequence name'),
      need(input$position > 0, 'Position must be greater than 0')
    )

    body <- list(callSetIds=list(callSetId()), referenceName=input$chr,
        start=input$position, end=input$position + 1)

    res <- POST(paste(endpoint, 'variants/search', sep=''),
        query=list(fields=
          'variants(names,referenceBases,alternateBases,calls(genotype))'),
        body=toJSON(body, auto_unbox=TRUE), config(token=google_token()),
        add_headers('Content-Type'='application/json'))
    stop_for_status(res)

    variants <- content(res)$variants
    shiny::validate(
      need(length(variants) > 0, 'No variants found for that position'))
    variant <- variants[[1]]
    variantName <- variant$names[[1]]

    genotype <- lapply(variant$calls[[1]]$genotype, function (g) {
      if (g == 0) {
        variant$referenceBases
      } else {
        variant$alternateBases[[g]]
      }
    })

    div(paste('the called genotype is', paste(genotype, collapse = ','),
        'for', variantName)[[1]])
  })
})
