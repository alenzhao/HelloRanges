### =========================================================================
### bedtools intersect command
### -------------------------------------------------------------------------
###

bedtools_intersect <- function(cmd = "--help") {
    do_R_call(R_bedtools_intersect, BEDTOOLS_INTERSECT_DOC, cmd)
}

stdinFile <- function() {
    message("Assuming BED format for 'stdin'")
    .R(BEDFile("stdin"))
}

pipeFile <- function(cmd) {
    message("Assuming BED format for piped input")
    cmd <- cmd
    .R(BEDFile(pipe(cmd)))
}

normA <- function(a) {
    if (identical(a, "stdin"))
        stdinFile()
    else if (is.character(a) && startsWith(a, "<"))
        pipeFile(substring(a, 2))
    else a
}

normB <- function(b) {
    normBToken <- function(bi) {
        if (bi == "stdin")
            stdinFile()
        else if (startsWith(bi, "<"))
            pipeFile(substring(bi, 2))
        else if (grepl("*", bi, fixed=TRUE))
            .R(Sys.glob(bi))
        else bi
    }
    if (hasRanges(b)) {
        return(b)
    }
    if (is(b, "List")) {
        return(stack(b, "b"))
    }
    if (isSingleString(b)) {
        b <- strsplit(b, ",", fixed=TRUE)[[1L]]
    }
    if (length(b) == 1L)
        normBToken(b)
    else as.call(c(quote(c), lapply(b, normBToken)))
}

importExtraColsArgs <- function(x, cols) {
    autoBamCols <- c("seqnames", "start", "cigar")
    if (isBam(x) && !all(cols %in% autoBamCols)) {
        .what <- setdiff(cols, c(autoBamCols, "names"))
        .param <- .R(ScanBamParam(what=.what))
        list(use.names = "names" %in% cols, param = .param)
    }
}

isResource <- function(x)
    is.character(x) || is(x, "RTLFile") || is(x, "RsamtoolsFile")

importA <- function(a, extraCols=character(0L), genome=quote(genome), ...) {
    a <- a; genome <- genome
    .gr_a <- objectName(a)
    if (isResource(a) || is.call(a)) {
        args <- c(importExtraColsArgs(a, extraCols), list(...))
        .import <- as.call(c(quote(import), a, genome=genome, args))
        R(.gr_a <- .import)
    } else {
        .a <- evalq(match.call()$a, parent.frame())
        R(.gr_a <- .a)
    }
    pushR(env=parent.frame())
    .gr_a
}

importB <- function(b, names=NULL, filenames=FALSE, extraCols=character(0L),
                    beforeStack = NULL, genome=quote(genome), ...)
{
    bval <- b; genome <- genome
    .gr_b <- objectName(b)
    args <- c(importExtraColsArgs(b, extraCols), list(...))
    if (is.character(b) || is.name(b) ||
        (is.call(b) && b[[1L]] == quote(BEDFile))) {
        .import <- as.call(c(quote(import), b, genome=genome, args))
        R(.gr_b <- .import)
    }
    else if (is.call(b)) {
        R(b <- bval)
        if (filenames) {
            R(names(b) <- vapply(b, as.character, character(1L)))
        } else if (!is.null(names)) {
            nms <- strsplit(names, ",", fixed=TRUE)[[1L]]
            R(names(b) <- nms)
        }
        .import <- .R(lapply(b, import, genome=genome))
        .import[names(args)] <- args
        R(bl <- List(.import))
        .bl <- if (!is.null(beforeStack))
                   .R(beforeStack(bl))
               else quote(bl)
        index.var <- deparse(substitute(b))
### FIXME: assumes list elements are of the same format and same "shape"
        R(.gr_b <- stack(.bl, index.var))
    } else {
        .b <- evalq(match.call()$b, parent.frame())
        R(.gr_b <- .b)
    }
    pushR(env=parent.frame())
    .gr_b
}

getFormat <- function(x) {
    if (is.vector(x)) {
        x <- x[[1L]]
    }
    if (is.call(x)) {
        sub("file$", "", tolower(x[[1L]]))
    } else if (is(x, "RTLFile") || is(x, "RsamtoolsFile")) {
        tolower(sub("File$", "", class(x)))
    } else if (is.character(x)) {
        file_ext(sub("[0-9]$", "", sub("\\.b?gz$", "", x)))
    }
}

hasFormat <- function(x, format) {
    identical(getFormat(x), format)
}

isBam <- function(x) {
    hasFormat(x, "bam") || is(x, "GAlignments") || is(x, "GAlignmentPairs")
}

isBed <- function(x) {
    hasFormat(x, "bed") || is(x, "GenomicRangesORGRangesList")
}

isVcf <- function(x) {
    hasFormat(x, "vcf") || is(x, "VCF") || is(x, "VRanges")
}

prepOverlapRanges <- function(x, split=FALSE) {
    gr_x <- parent.frame()[[paste0(".gr_", deparse(substitute(x)))]]
    eval(substitute({
        if (isBam(x)) {
            if (split) {
                .R(grglist(gr_x)) # needed for pintersect()
            } else {
                .R(granges(gr_x))
            }
        } else if (isBed(x) && split) {
            .R(blocks(gr_x))
        } else {
            .R(gr_x)
        }
    }, list(gr_x=gr_x)))
}

prepAnsRanges <- function(x, bed) {
    gr_x <- parent.frame()[[paste0(".gr_", deparse(substitute(x)))]]
    eval(substitute({
        if (bed) {
            if (isBam(x)) {
                .R(asBED(gr_x))
            } else if (isVcf(x)) {
                .R(as(gr_x, "VRanges"))
            }
            else {
                .R(gr_x)
            }
        } else {
            .R(gr_x)
        }
    }, list(gr_x=gr_x)))
}

objectName <- function(x) {
    label <- deparse(substitute(x))
    eval(substitute({
        if (isBam(x))
            .R(ga_x)
        else if (isVcf(x))
            .R(vcf_x)
        else .R(gr_x)
    }, list(gr_x = as.name(paste0("gr_", label)),
            ga_x = as.name(paste0("ga_", label)),
            vcf_x = as.name(paste0("vcf_", label)))))
}

importGenome <- function(g) {
    if (is(g, "Seqinfo")) {
        .g <- evalq(match.call()$g, parent.frame())
        R(genome <- .g)
    } else {
        g <- g
        haveGenomeFile <- identical(file_ext(g), "genome")
        if (haveGenomeFile) {
            R(genome <- import(g))
        } else {
            R(genome <- Seqinfo(genome=g))
        }
    }
    pushR(env=parent.frame())
}

intersectPairs <- function(is_grl_a, is_grl_b, ignore.strand,
                           strict.strand=FALSE)
{
    ignore.strand <- ignore.strand
    pairs <- quote(pairs)
    .pintersect <- if (is_grl_a && is_grl_b) quote(intersect)
                   else quote(pintersect)
    if (strict.strand) {
        .R(.pintersect(pairs, ignore.strand=ignore.strand, strict.strand=TRUE))
    } else {
        .R(.pintersect(pairs, ignore.strand=ignore.strand))
    }
}

overlapWidth <- function(is_grl_a, is_grl_b, ...)
{
    .pairInt <- intersectPairs(is_grl_a, is_grl_b, ...)
    R(olap <- .pairInt)
    pushR(env=parent.frame())
    if (is_grl_a || is_grl_b)
        .R(sum(width(olap)))
    else .R(width(olap))
}

restrictByFraction <- function(f, F, r, e, have_f, have_F,
                               is_grl_a, is_grl_b, ...)
{
    f <- f; F <- F; r <- r; e <- e;
    pairs <- quote(pairs)
    if (have_f && have_F && r) {
        stop("only one of -f and -F may be specified with -r")
    }
    .width_olap <- overlapWidth(is_grl_a, is_grl_b, ...)
    if (r) {
        if (have_f) {
            F <- f
            have_F <- TRUE
        } else {
            f <- F
            have_f <- TRUE
        }
    }
    if (have_f) {
        .width_first <- if (is_grl_a) .R(sum(width(first(pairs))))
                        else .R(width(first(pairs)))
        .keep <- .R(.width_olap / .width_first >= f)
    }
    if (have_F) {
        .width_second <- if (is_grl_b) .R(sum(width(second(pairs))))
                         else .R(width(second(pairs)))
        .keep_F <- .R(.width_olap / .width_second >= F)
        if (have_f) {
            .keep <- if (e) .R(.keep | .keep_F) else .R(.keep & .keep_F)
        } else {
            .keep <- .keep_F
        }
    }
    R(keep <- .keep)
    pushR(env=parent.frame())
    quote(keep)
}

.findOverlaps <- function(.gr_a_o, .gr_b_o, ignore.strand, f, r, e,
                          ret.pairs)
{
    .gr_a_o <- .gr_a_o; .gr_b_o <- .gr_b_o; ignore.strand <- ignore.strand
    .findOverlaps <-
        if (ret.pairs) {
            .R(pairs <- findOverlapPairs(.gr_a_o, .gr_b_o,
                                         ignore.strand=ignore.strand))
        } else {
            .R(hits <- findOverlaps(.gr_a_o, .gr_b_o,
                                    ignore.strand=ignore.strand))
        }
    ans <- if (f == 1.0 && !e) {
               .findOverlaps[[3L]]$type <- if (r) "equal" else "within"
               FALSE
           } else !identical(f, formals(R_bedtools_intersect)$f)
    pushR(.findOverlaps, parent.frame())
    ans
}

hasRanges <- function(x) {
    hasMethod(ranges, class(x))
}

R_bedtools_intersect <- function(a, b, ubam=FALSE, bed=FALSE,
                                 wa=FALSE, wb=FALSE, loj=FALSE, wo=FALSE,
                                 wao=FALSE, u=FALSE, c=FALSE, v=FALSE,
                                 f=1e-9, F=1e-9, r=FALSE, e=FALSE, s=FALSE,
                                 S=FALSE, split=FALSE, g=NA_character_,
                                 header=FALSE, # ignored
                                 names=NULL, filenames=FALSE, sortout=FALSE)
{
    stopifnot(isSingleString(a) || hasRanges(a),
              (is.character(b) && !anyNA(b) && length(b) >= 1L) || hasRanges(b),
              isTRUEorFALSE(ubam),
              isTRUEorFALSE(bed),
              isTRUEorFALSE(wa),
              isTRUEorFALSE(wb),
              isTRUEorFALSE(loj),
              isTRUEorFALSE(wo),
              isTRUEorFALSE(wao),
              isTRUEorFALSE(u),
              isTRUEorFALSE(c),
              isTRUEorFALSE(v),
              isSingleNumber(f), f > 0, f <= 1,
              isSingleNumber(F), F > 0, F <= 1,
              isTRUEorFALSE(r),
              isTRUEorFALSE(e),
              isTRUEorFALSE(s),
              isTRUEorFALSE(S), !(s && S),
              isTRUEorFALSE(split),
              isSingleStringOrNA(g),
              isTRUEorFALSE(header),
              isTRUEorFALSE(filenames),
              isTRUEorFALSE(sortout))

    if (!is.null(names)) {
        stopifnot(is.character(names), !anyNA(names),
                  length(names) == length(b))
    }

    if (ubam) {
        stop("'ubam' is not yet supported")
    }
    
    importGenome(g)
    
    a <- normA(a)
    b <- normB(b)
    
    .gr_a <- importA(a)
    .gr_b <- importB(b, names, filenames)
    
    .gr_a_o <- prepOverlapRanges(a, split)
    .gr_b_o <- prepOverlapRanges(b, split)

    if ((isBam(a) || isVcf(a)) && !bed) {
        wa <- TRUE # no way to represent overlapping interval
    }
    
    if (wao) {
        wo <- TRUE
        loj <- TRUE
    }
    if (wo || loj) {
        wa <- wb <- TRUE
    }
    
    if (S) {
        .gr_b_o <- .R(invertStrand(.gr_b_o))
    }

    ignore.strand <- !(s || S)

    have_f <- !identical(f, formals(sys.function())$f)
    have_F <- !identical(F, formals(sys.function())$F)
    fracRestriction <- have_f || have_F
    
    .gr_a_ans <- prepAnsRanges(a, bed)
    .gr_b_ans <- prepAnsRanges(b, bed)

    ## The pairs are always formed from the overlap ranges, but we do
    ## not always return the overlap ranges, particularly for BAMs.
    ## In those cases, we need the hits to generate the answer, even
    ## when we would otherwise just want the pairs.
    olapNotAns_a <- wa && !identical(.gr_a_o, .gr_a_ans)
    olapNotAns_b <- wb && !identical(.gr_b_o, .gr_b_ans)
    
    needPairs <- !(u || c || v || loj)
    needHits <- !needPairs || olapNotAns_a || olapNotAns_b
    if (have_f || have_F || !(u || c || v)) {
        have_f <- .findOverlaps(.gr_a_o, .gr_b_o, ignore.strand,
                                ret.pairs=!needHits, f, r, e)
    }

    is_grl_a <- split && (isBed(a) || isBam(a))
    is_grl_b <- split && (isBed(b) || isBam(b))

    .pintersect <- if (is_grl_a && is_grl_b) quote(intersect)
                   else quote(pintersect)
    .pairInt <- .R(.pintersect(pairs, ignore.strand=ignore.strand))

    if (have_f || have_F) {
        if (needHits) {
            R(pairs <- Pairs(.gr_a_o, .gr_b_o, hits=hits))
        }
        keep <- restrictByFraction(f, F, r, e, have_f, have_F,
                                   is_grl_a, is_grl_b, ignore.strand)
        olap <- quote(olap)
        if (needHits) {
            R(hits <- hits[keep])
        } else {
            R(pairs <- pairs[keep])
        }
    }

    if (c) {
        rm(c)
        R(ans <- .gr_a_ans)
        .c <- if (have_f || have_F) {
            .R(countQueryHits(hits))
        } else {
            .R(countOverlaps(.gr_a_o, .gr_b_o,
                             ignore.strand=ignore.strand))
        }
        R(mcols(ans)$overlap_count <- .c)
        return(R(ans))
    }

    if ((u || v) && olapNotAns_a && !s && !S) {
        .gr_b_o <- .R(unstrand(.gr_b_o))
    }
    
    if (u) {
        return(if (fracRestriction) {
                   R(.gr_a_ans[countQueryHits(hits) > 0L])
               } else {
                   if (olapNotAns_a) {
                       R(.gr_a_ans[.gr_a_o %over% .gr_b_o])
                   } else {
                       R(subsetByOverlaps(.gr_a_o, .gr_b_o,
                                          ignore.strand=ignore.strand))
                   }
               })
    }

    if (v) {
        return(if (fracRestriction) {
                   R(.gr_a_ans[countQueryHits(hits) == 0L])
               } else {
                   if (olapNotAns_a) {
                       R(.gr_a_ans[.gr_a_o %outside% .gr_b_o])
                   } else {
                       R(subsetByOverlaps(.gr_a_o, .gr_b_o, invert=TRUE,
                                          ignore.strand=ignore.strand))
                   }
               })
    }
    
    if (loj) {
        R(ans <- pair(.gr_a_ans, .gr_b_ans, hits, all.x=TRUE))
    } else if (wa && wb) {
        if (olapNotAns_a || olapNotAns_b) {
            R(ans <- Pairs(.gr_a_ans, .gr_b_ans, hits=hits))
        } else {
            R(ans <- pairs)
        }
    } else if (wa) {
        if (olapNotAns_a) {
            R(ans <- .gr_a_ans[queryHits(hits)])
        } else {
            R(ans <- first(pairs))
        }
    } else { # return intersection
        if (fracRestriction) {
            R(ans <- olap[keep])
        } else {
            if (is_grl_a || is_grl_b) {
                .pairInt <- .R(asBED(.pairInt))
            }
            if (wb) {
                if (olapNotAns_b) {
                    .second <- .R(.gr_b_ans[subjectHits(hits)])
                } else {
                    .second <- .R(second(pairs))
                }
                R(ans <- Pairs(.pairInt, .second))
            } else {
                R(ans <- .pairInt)
            }
        }
    }
    
    if (wo) {
        .o <- if (fracRestriction && !loj) {
                  if (is_grl_a || is_grl_b)
                      .R(sum(width(olap))[keep])
                  else .R(width(olap)[keep])
        } else if (loj || olapNotAns_a || olapNotAns_b) {
            if (loj) {
                R(pairs <- pair(.gr_a_o, .gr_b_o, hits, all.x=TRUE))
            } else {
                R(pairs <- Pairs(.gr_a_o, .gr_b_o, hits=hits))
            }
            olap <- quote(olap)
            overlapWidth(is_grl_a, is_grl_b, ignore.strand)
        } else {
            .R(width(.pintersect(ans, ignore.strand=ignore.strand)))
        }
        R(mcols(ans)$overlap_width <- .o)
    }

    if (sortout) {
        if (wb) {
            R(ans <- ans[order(first(ans))])
        } else {
            R(ans <- sort(ans))
        }
    }

    R(ans)
}

BEDTOOLS_INTERSECT_DOC <-
    "Usage:
       bedtools_intersect [options]
     Options:
       -a <FILE>  BAM/BED/GFF/VCF file A. Each feature in A is compared to B
          in search of overlaps. Use 'stdin' if passing A with a UNIX pipe.
       -b <FILE1,...>  One or more BAM/BED/GFF/VCF file(s) B. Use 'stdin' if
          passing B with a UNIX pipe. -b may be followed with multiple
          databases and/or wildcard (*) character(s).
       --ubam  Write uncompressed BAM output. The default is write compressed
               BAM output.
       --bed  When using BAM input, write output as BED. The default is to
              write output in BAM.
       --wa  Write the original entry in A for each overlap.
       --wb  Write the original entry in B for each overlap. Useful for knowing
             what A overlaps. Restricted by -f and -r.
       --loj  Perform a 'left outer join'. That is, for each feature in A
              report each overlap with B. If no overlaps are found, report a
              NULL feature for B.
       --wo  Write the original A and B entries plus the number of base pairs
             of overlap between the two features. Only A features with overlap
             are reported. Restricted by -f and -r.
       --wao  Write the original A and B entries plus the number of base pairs
              of overlap between the two features. However, A features w/o
              overlap are also reported with a NULL B feature and overlap = 0.
              Restricted by -f and -r.
       -u  Write original A entry once if any overlaps found in B. In other
           words, just report the fact at least one overlap was found in B.
           Restricted by -f and -r.
       -c  For each entry in A, report the number of hits in B while
           restricting to -f. Reports 0 for A entries that have no overlap
           with B. Restricted by -f and -r.
       -v  Only report those entries in A that have no overlap in B.
           Restricted by -f and -r.
       -f <frac>  Minimum overlap required as a fraction of A [default: 1e-9].
       -F <frac>  Minimum overlap required as a fraction of B [default: 1e-9].
       -r  Require that the fraction of overlap be reciprocal for A and B. In
           other words, if -f is 0.90 and -r is used, this requires that B
           overlap at least 90% of A and that A also overlaps at least 90% of B.
       -e  Require that the minimum fraction be satisfied for A _OR_ B. In
           other words, if -e is used with -f 0.90 and -F 0.10 this requires
           that either 90% of A is covered OR 10% of B is covered. Without -e,
           both fractions would have to be satisfied.
       -s  Force strandedness. That is, only report hits in B that overlap A
           on the same strand. By default, overlaps are reported without
           respect to strand.
       -S  Require different strandedness. That is, only report hits in B that
           overlap A on the _opposite_ strand. By default, overlaps are
           reported without respect to strand.
       --split  Treat split BAM (i.e., having an 'N' CIGAR operation) or BED12
                entries as distinct BED intervals.
       -g <path>  Specify a genome file or identifier that defines the order
                  and size of the sequences.
       --header  Print the header from the A file prior to results.
       --names <name,...>  When using multiple databases (-b), provide an alias
               for each that will appear instead of a fileId when also printing
               the DB record.
       --filenames  When using multiple databases (-b), show each complete
                    filename instead of a fileId when also printing the DB
                    record.
       --sortout  When using multiple databases (-b), sort the output DB hits
                  for each record."

do_bedtools_intersect <- make_do(R_bedtools_intersect)
