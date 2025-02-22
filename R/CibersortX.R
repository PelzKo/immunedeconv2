#' Setting the CIBERSORTx Credentials
#'
#' @param email The email which was used to register on the website.
#' @param token The token provided by the website.
#'
#' @export
#'
#' @examples
#' set_cibersortx_credentials("max.mustermann@online.de", "7250fe7ajc322eeta192d163d62e6399")
set_cibersortx_credentials <- function(email, token) {
  assign("cibersortx_email", email, envir = config_env)
  assign("cibersortx_token", token, envir = config_env)
}


#' Signature matrix creation with CIBERSORTx
#'
#' @param single_cell_object A matrix with the single-cell data. Rows are genes, columns are
#'   samples. Row and column names need to be set.
#' @param cell_type_annotations A vector of the cell type annotations. Has to be in the same order
#'   as the samples in single_cell_object.
#' @param verbose Whether to produce an output on the console.
#' @param container The container used ot run the method. The possibilities are 'docker' (default) or
#'   'apptainer'. You can check if the container can be called with the check_container() function
#' @param container_path the path where the apptainer .sif file is/will be stored (optional)
#' @param input_dir The directory in which the input files can be found (or are created in).
#'   Default is a temporary directory.
#' @param output_dir The directory in which the output files are saved. Default is a temporary
#'   directory.
#' @param display_heatmap Whether to display the generated heatmap.
#' @param k_max Maximum condition number (default: 999). Will be added to the file name.
#' @param ... Additional parameters supplied to the algorithm. Options are:
#' \itemize{
#'  \item g_min <int> Minimum number of genes per cell type in sig. matrix (default: 300).
#'  \item g_max <int> Maximum number of genes per cell type in sig. matrix (default: 500).
#'  \item q_value <int> Q-value threshold for differential expression (default: 0.01).
#'  \item filter <bool> Remove non-hematopoietic genes (default: FALSE).
#'  \item remake <bool> Remake signature gene matrix (default: False).
#'  \item replicates <int> Number of replicates to use for building scRNAseq reference file
#'    (default: 5).
#'  \item sampling <float> Fraction of available single cell GEPs selected using random sampling
#'    (default: 0.5).
#'  \item fraction <float> Fraction of cells of same identity showing evidence of expression
#'    (default: 0.75).
#' }
#'
#' @return The signature matrix. Rows are genes, columns are cell types.
#' @export
#'
build_model_cibersortx <- function(single_cell_object, cell_type_annotations,
                                   container = c("docker", "apptainer"),
                                   container_path = NULL,
                                   verbose = FALSE, input_dir = NULL,
                                   output_dir = NULL, display_heatmap = FALSE,
                                   k_max = 999, ...) {
  if (is.null(single_cell_object)) {
    stop("Parameter 'single_cell_object' is missing or null, but it is required.")
  }
  if (is.null(cell_type_annotations)) {
    stop("Parameter 'cell_type_annotations' is missing or null, but it is required.")
  }

  container <- match.arg(container)

  # if (!check_container(container)) {
  #  return(NULL)
  # }

  check_credentials()

  temp_dir <- tempdir()

  if (container == "apptainer") {
    container_path <- setup_apptainer_container(container_path)
  }

  if (is.null(input_dir)) {
    input_dir <- temp_dir
  }
  if (is.null(output_dir)) {
    output_dir <- temp_dir
  }

  if (class(single_cell_object)[1] != "character") {
    transform_and_save_single_cell(single_cell_object, cell_type_annotations, input_dir, verbose)
    single_cell_object_filename <- "sample_file_for_cibersort.txt"
  } else {
    single_cell_object_filename <- single_cell_object
  }
  command_to_run <- create_container_command(input_dir, output_dir, container, container_path,
    method = "create_sig",
    verbose = verbose,
    refsample = single_cell_object_filename,
    k_max = k_max, ...
  )

  if (verbose) {
    message(command_to_run)
  }

  if (!verbose) {
    if (Sys.info()["sysname"] == "Windows") {
      message("The windows implementation requires verbose mode. It is now switched on.")
      verbose <- TRUE
    }
  }

  filebase <- paste0(
    "CIBERSORTx_sample_file_for_cibersort_inferred_phenoclasses.CIBERSORTx_sample",
    "_file_for_cibersort_inferred_refsample.bm.K", k_max
  )
  filename_sig_matrix <- paste0(filebase, ".txt")
  full_path <- paste0(input_dir, "/", filename_sig_matrix)

  if (file.exists(full_path)) {
    file.remove(full_path)
  }

  code <- system(command_to_run, ignore.stdout = !verbose, ignore.stderr = !verbose)
  if (code != 0) {
    message(paste0(
      "Something went wrong: Error code ", code, ". Please try again with ",
      "'verbose=TRUE'"
    ))
  }

  if (display_heatmap) {
    filename_heatmap <- paste0(filebase, ".pdf")
    Biobase::openPDF(normalizePath(paste0(output_dir, "/", filename_heatmap)))
  }

  sig_matrix <- verbose_wrapper(verbose)(as.data.frame(readr::read_tsv(
    paste0(output_dir, "/", filename_sig_matrix)
  )))
  rownames(sig_matrix) <- sig_matrix$NAME

  return(as.matrix.data.frame(sig_matrix[, -1]))
}

#' Deconvolute with CIBERSORTx
#'
#' @param bulk_gene_expression A matrix or dataframe with the bulk data. Rows are genes, columns
#'   are samples. Row and column names need to be set. Can also just be the filename of the bulk
#'   expression data in the correct format (generated by using this method). The file needs to be
#'   in the folder "input_dir".
#' @param signature The signature matrix. Can also be the filename of the signature matrix in the
#'   correct format (generated by using this method). The file needs to be in the folder
#'   "input_dir".
#' @param single_cell_object A matrix with the single-cell data. Rows are genes, columns are
#'   samples. Row and column names need to be set. (optional, only necessary if S- or B-mode are used)
#' @param cell_type_annotations A vector of the cell type annotations. Has to be in the same order
#'   as the samples in single_cell_object. (optional, only necessary if S- or B-mode are used)
#' @param rmbatch_B_mode Run B-mode batch correction (default: FALSE). Supply single_cell_object if TRUE.
#' @param rmbatch_S_mode Run S-mode batch correction (default: FALSE). Supply single_cell_object if TRUE.
#' @param verbose Whether to produce an output on the console.
#' @param container The container used to run the method. The possibilities are 'docker' (default) or
#'   'apptainer'
#' @param container_path the path where the apptainer .sif file is/will be stored (optional)
#' @param input_dir The folder in which the input files can be found (or are created in). Default
#'   is a temporary directory.
#' @param output_dir The directory in which the output files are saved. Default is a temporary
#'   directory.
#' @param display_extra_info Whether to print the "P.value","Correlation" and "RMSE" calculated
#'   by CIBERSORTx.
#' @param label The label which will be added to the file name. Default is "none", adding no label
#'   at all.
#' @param ... Additional parameters supplied to the algorithm. Options are:
#' \itemize{
#'  \item perm <int> No. of permutations for p-value calculation (default: 0).
#'  \item source_GEPs <file_name>  Signature matrix GEPs for batch correction (default: sigmatrix).
#'  \item qn <bool>  Run quantile normalization (default: FALSE).
#'  \item absolute <bool>  Run absolute mode (default: FALSE).
#'  \item abs_method <char>  Pick absolute method ("sig.score" (default) or "no.sumto1").
#' }
#'
#' @return A matrix with the probabilities of each cell-type for each individual. Rows are
#'   individuals, columns are cell types.
#' @export
#'
deconvolute_cibersortx <- function(bulk_gene_expression, signature,
                                   single_cell_object = NULL,
                                   cell_type_annotations = NULL,
                                   rmbatch_B_mode = FALSE,
                                   rmbatch_S_mode = FALSE,
                                   verbose = FALSE,
                                   container = c("docker", "apptainer"),
                                   container_path = NULL,
                                   input_dir = NULL, output_dir = NULL,
                                   display_extra_info = FALSE, label = "none", ...) {
  if (is.null(bulk_gene_expression)) {
    stop("Parameter 'bulk_gene_expression' is missing or null, but it is required.")
  }
  if (is.null(signature)) {
    stop("Parameter 'signature' is missing or null, but it is required.")
  }

  container <- match.arg(container)
  # if (!check_container(container)) {
  #  return(NULL)
  # }


  check_credentials()
  temp_dir <- tempdir()

  if (container == "apptainer") {
    apptainer_container_path <- setup_apptainer_container(container_path)
  } else {
    apptainer_container_path <- NULL
  }


  if (is.null(input_dir)) {
    input_dir <- temp_dir
  }
  if (is.null(output_dir)) {
    output_dir <- temp_dir
  }

  if (rmbatch_B_mode || rmbatch_S_mode) {
    if (is.null(single_cell_object)) {
      stop("Parameter 'single_cell_object' is missing or null, but it is required.")
    }
    if (is.null(cell_type_annotations)) {
      stop("Parameter 'cell_type_annotations' is missing or null, but it is required.")
    }
    if (class(single_cell_object)[1] != "character") {
      transform_and_save_single_cell(single_cell_object, cell_type_annotations, input_dir, verbose)
      single_cell_object_filename <- "sample_file_for_cibersort.txt"
    } else {
      single_cell_object_filename <- single_cell_object
    }
  }
  if (class(signature)[1] != "character") {
    sig <- paste0(input_dir, "/signature_matrix.txt")
    readr::write_tsv(data.frame("NAME" = rownames(signature), signature), sig)
    sigmatrix_filename <- "signature_matrix.txt"
  } else {
    sigmatrix_filename <- signature
  }
  if (class(bulk_gene_expression)[1] != "character") {
    transform_and_save_bulk(bulk_gene_expression, input_dir, verbose)
    bulk_gene_expression_filename <- "mixture_file_for_cibersort.txt"
  } else {
    bulk_gene_expression_filename <- bulk_gene_expression
  }
  unique_id <- uuid::UUIDgenerate(TRUE)
  if (label == "none") {
    label <- unique_id
  } else {
    label <- paste0(label, "_", unique_id)
  }




  if (rmbatch_B_mode || rmbatch_S_mode) {
    command_to_run <- create_container_command(input_dir, output_dir, container, apptainer_container_path,
      method = "impute_cell_fractions", verbose,
      refsample = single_cell_object_filename,
      rmbatch_B_mode = rmbatch_B_mode, rmbatch_S_mode = rmbatch_S_mode,
      sigmatrix = sigmatrix_filename, mixture = bulk_gene_expression_filename, label = label, ...
    )
    filename_cell_props <- paste0("CIBERSORTx_", label, "_Adjusted.txt")
  } else {
    command_to_run <- create_container_command(input_dir, output_dir, container, apptainer_container_path,
      method = "impute_cell_fractions", verbose = verbose,
      sigmatrix = sigmatrix_filename, mixture = bulk_gene_expression_filename, label = label, ...
    )
    filename_cell_props <- paste0("CIBERSORTx_", label, "_Results.txt")
  }

  cell_props_full_path <- paste0(output_dir, "/", filename_cell_props)

  if (verbose) {
    message(command_to_run)
  }

  if (!verbose) {
    if (Sys.info()["sysname"] == "Windows") {
      message("The windows implementation requires verbose mode. It is now switched on.")
      verbose <- TRUE
    }
  }

  code <- system(command_to_run, ignore.stdout = !verbose, ignore.stderr = !verbose)
  if (code != 0) {
    message(paste0(
      "Something went wrong: Error code ", code, ". Please try again with ",
      "'verbose=TRUE'"
    ))
  }

  cell_props_tmp <- verbose_wrapper(verbose)(as.data.frame(readr::read_tsv(
    cell_props_full_path
  )))
  cell_props <- cell_props_tmp
  rm(cell_props_tmp)
  rownames(cell_props) <- cell_props$Mixture
  cell_props <- cell_props[, -1]

  extra_cols <- c("Correlation", "RMSE", "P-value")
  if (display_extra_info) {
    print(cell_props[, extra_cols])
  } else {
    cell_props <- cell_props[, !names(cell_props) %in% extra_cols]
    colnames(cell_props) <- colnames(signature)
  }


  return(as.matrix.data.frame(cell_props))
}

#' Creation of the single cell data file in the CIBERSORTx required format
#'
#' @param sc_matrix The single cell data as a matrix.
#' @param cell_types A Vector of the cell type annotations. Has to be in the same order as the
#'   samples in single_cell_object.
#' @param path The folder in which the file should be saved.
#' @param verbose Whether to produce an output on the console.
#'
#' @return The path to the single cell data file
#'
transform_and_save_single_cell <- function(sc_matrix, cell_types, path, verbose = FALSE) {
  colnames(sc_matrix) <- cell_types
  output <- rbind(colnames(sc_matrix), sc_matrix)
  rownames(output) <- c("GeneSymbol", rownames(sc_matrix))
  output <- data.frame("GeneSymbol" = rownames(output), output)
  output_file <- paste0(path, "/sample_file_for_cibersort.txt")
  readr::write_tsv(output, output_file, col_names = FALSE)
  if (verbose) {
    message(paste(
      "Single cell matrix was saved successfully and can be found at: ",
      output_file
    ))
  }
  return(output_file)
}

#' Creation of the bulk data file in the CIBERSORTx required format
#'
#' @param bulk The bulk data as a matrix.
#' @param path The folder in which the file should be saved.
#' @param verbose Whether to produce an output on the console.
#'
#' @return The path to the bulk data file.
#'
transform_and_save_bulk <- function(bulk, path, verbose = FALSE) {
  output_file <- paste0(path, "/mixture_file_for_cibersort.txt")
  readr::write_tsv(data.frame("Gene" = rownames(bulk), bulk), output_file)
  if (verbose) {
    message(paste(
      "Bulk data matrix was saved successfully and can be found at: ",
      output_file
    ))
  }
  return(output_file)
}

#' Creation of the docker command
#'
#' @param in_dir The folder in which the input files can be found (or are created in). Default is
#'   a temporary directory.
#' @param out_dir The directory in which the output files are saved. Default is a temporary
#'   directory.
#' @param container The container to use. Possibilities are 'docker' and 'apptainer'
#' @param apptainer_container_path The path where the apptainer container is stored (optional)
#' @param method Which docker command should be be created. For signature matrix creation use
#'   "create_sig", for cell type deconvolution use "impute_cell_fractions".
#' @param verbose Whether to produce an output on the console.
#' @param ... The additional parameters for the command.
#'
#' @return A valid docker command to be run.
#'
create_container_command <- function(in_dir, out_dir,
                                     container = c("docker", "apptainer"),
                                     apptainer_container_path = NULL,
                                     method = c("create_sig", "impute_cell_fractions"),
                                     verbose = FALSE, ...) {
  if (container == "docker") {
    base <- paste0(
      "docker run -v ", in_dir, ":/src/data:z -v ", out_dir,
      ":/src/outdir:z cibersortx/fractions --single_cell TRUE"
    )
  } else {
    base <- paste0(
      "apptainer exec --no-home -c -B ", in_dir,
      "/:/src/data -B ", out_dir, "/:/src/outdir ",
      apptainer_container_path, " /src/CIBERSORTxFractions --single_cell TRUE"
    )
  }


  if (verbose) {
    base <- paste(base, "--verbose TRUE")
  }
  check_credentials()
  credentials <- paste(
    "--username", get("cibersortx_email", envir = config_env), "--token",
    get("cibersortx_token", envir = config_env)
  )
  options <- get_method_options(method, ...)
  command <- paste(base, credentials, options)
  return(command)
}

#' Creation of the additional parameter sting for the docker command
#'
#' @param method The method for which the parameter string should be generated. Options are
#'   "create_sig" and "impute_cell_fractions".
#' @param ... The parameter values itself, being passed on to the correct method.
#'
#' @return A string in the correct format for the docker command, containing all parameters of the
#'   desired method.
#'
get_method_options <- function(method = c("create_sig", "impute_cell_fractions"), ...) {
  if (method == "create_sig") {
    return(get_signature_matrix_options(...))
  } else if (method == "impute_cell_fractions") {
    return(get_cell_fractions_options(...))
  } else {
    stop(paste("Method", method, "is not valid"))
  }
}

#' Creation of the options of the "get signature matrix" docker command
#'
#' @param refsample The filename of the single cell data.
#' @param g_min <int> Minimum number of genes per cell type in sig. matrix.
#' @param g_max <int> Maximum number of genes per cell type in sig. matrix.
#' @param q_value <int> Q-value threshold for differential expression.
#' @param filter <bool> Remove non-hematopoietic genes.
#' @param k_max <int> Maximum condition number. Will be added to the file name.
#' @param remake <bool> Remake signature gene matrix.
#' @param replicates <int> Number of replicates to use for building scRNAseq reference file.
#' @param sampling <float> Fraction of available single cell GEPs selected using random sampling.
#' @param fraction <float> Fraction of cells of same identity showing evidence of expression.
#'
#'
#' @return A string in the correct format for the docker command, containing all parameters.
#'
get_signature_matrix_options <- function(refsample, g_min = 300, g_max = 500, q_value = 0.01,
                                         filter = FALSE, k_max = 999, remake = FALSE,
                                         replicates = 5, sampling = 0.5, fraction = 0.75) {
  return(paste(
    "--refsample", refsample, "--G.min", g_min, "--G.max", g_max, "--q.value", q_value, "--filter",
    filter, "--k.max", k_max, "--remake", remake, "--replicates", replicates, "--sampling",
    sampling, "--fraction", fraction
  ))
}


#' Creation of the options of the "get cell fractions" docker command
#'
#'
#' @param sigmatrix The filename of the signature matrix.
#' @param mixture The filename of the bulk expression data.
#' @param rmbatch_B_mode <bool>  Run B-mode batch correction (default: FALSE).
#' @param rmbatch_S_mode <bool>  Run S-mode batch correction (default: FALSE).
#' @param perm <int> No. of permutations for p-value calculation (default: 0).
#' @param label The label which will be added to the file name. Default is "none", adding no label
#'   at all.
#' @param refsample The filename of the single cell data.
#' @param source_GEPs <file_name>  Signature matrix GEPs for batch correction (default: sigmatrix).
#' @param qn <bool>  Run quantile normalization (default: FALSE).
#' @param absolute <bool>  Run absolute mode (default: FALSE).
#' @param abs_method <char>  Pick absolute method ("sig.score" (default) or "no.sumto1").
#'
#' @return A string in the correct format for the docker command, containing all parameters.
#'
get_cell_fractions_options <- function(sigmatrix, mixture,
                                       rmbatch_B_mode = FALSE, rmbatch_S_mode = FALSE,
                                       perm = 0, label = "none",
                                       refsample = NULL,
                                       source_GEPs = sigmatrix, qn = FALSE,
                                       absolute = FALSE, abs_method = "sig.score") {
  option_string <- paste(
    "--mixture", mixture, "--sigmatrix", sigmatrix, "--perm", perm, "--label", label,
    "--rmbatchBmode", rmbatch_B_mode, "--rmbatchSmode", rmbatch_S_mode, "--sourceGEPs", source_GEPs,
    "--QN", qn, "--absolute", absolute, "--abs_method", abs_method
  )
  if (!is.null(refsample)) {
    option_string <- paste(option_string, "--refsample", refsample)
  }
  return(option_string)
}

#' Checks that the email and token variables are set
#'
check_credentials <- function() {
  assertthat::assert_that(exists("cibersortx_email", envir = config_env),
    msg = paste(
      "CIBERSORTx email for credentials is missing. Please call",
      "set_cibersortx_credentials(email,token) first."
    )
  )
  assertthat::assert_that(exists("cibersortx_token", envir = config_env),
    msg = paste(
      "CIBERSORTx token for credentials is missing. Please call",
      "set_cibersortx_credentials(email,token) first."
    )
  )
}
