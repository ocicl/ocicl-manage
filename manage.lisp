(asdf:load-system :cl-github-v3)
(asdf:load-system :legit)
(asdf:load-system :cl-ppcre)
(asdf:load-system :split-sequence)
(asdf:load-system :privacy-output-stream)

(setf cl-github:*username* (uiop:getenv "GITHUB_USER"))
(setf cl-github:*password* (uiop:getenv "GITHUB_PASSWORD"))

;; ocicl-manage pat
(defparameter +github-pat+ (uiop:getenv "GITHUB_PAT"))

;; Pull all ocicl repos from github
(defvar *repos* (cl-github:list-repositories :org "ocicl"))

;; Hide all of our secrets
(setf *standard-output* (make-instance 'privacy-output-stream:privacy-output-stream
                                       :stream *standard-output*
                                       :secrets (list cl-github:*username*
                                                      cl-github:*password*
                                                      +github-pat+)))
(setf *error-output* (make-instance 'privacy-output-stream:privacy-output-stream
                                    :stream *error-output*
                                    :secrets (list cl-github:*username*
                                                   cl-github:*password*
                                                   +github-pat+)))

;; Remove admin repos/directories
(dolist (repo '("ocicl" "ocicl-admin" "ocicl-manage" "ocicl-sandbox" "ocicl-action" "request-system-additions-here" "friends" ".github" ))
  (setf *repos* (remove-if (lambda (n) (string= repo (getf n :name))) *repos*)))

(dolist (repo *repos*)
  (uiop:delete-directory-tree (merge-pathnames (concatenate 'string (getf repo :name) "/")) :if-does-not-exist :ignore :validate t))

(dolist (repo *repos*)
  (let ((full-repo (format nil "https://~A:~A@github.com:/ocicl/~A" cl-github:*username* +github-pat+ (getf repo :name))))
    (format t "Cloning ~A~%" full-repo)
    (legit:git-clone full-repo)))

(defun parse-readme.org (filename)
  (with-open-file (stream filename)
    (let* ((project-name (string-trim " *" (read-line stream nil)))
           body
           table)

      ;; Read the body till we find a line starting with "|---------"
      (loop for line = (read-line stream nil)
            until (or (not line)
                      (cl-ppcre:scan "\\|---------\\+" line))
            do (setf body (concatenate 'string body (format nil "~A~%" line))))

      ;; Read the table (stop reading once another "|---------+" is detected or the file ends)
      (loop for line = (read-line stream nil)
            until (or (not line)
                      (cl-ppcre:scan "\\|---------\\+" line))
            do (setf table (concatenate 'string table (format nil "~A~%" line))))

      ;; Parse the table and convert to hashtable
      (let ((hash-table (make-hash-table :test 'equal))
            (table-lines (cl-ppcre:split #\Newline table :limit 0)))
        (loop for line in table-lines
              for match = (cl-ppcre:scan "\\|.+?\\|.+?\\|" line)
              when match
                do (let* ((parts (cl-ppcre:split "\\|" line))
                          (key (string-trim " " (nth 1 parts)))
                          (value (string-trim " " (nth 2 parts))))
                     (setf (gethash key hash-table) value)))

        ;; Return the three values
        (values project-name body hash-table)))))

(dolist (repo *repos*)
  (handler-case
      (let (project-name description table)
        (multiple-value-setq (project-name description table)
          (parse-readme.org (format nil "~A/README.org" (getf repo :name))))

	(unless (gethash "deadlink" table)
          ;; Check that the table is complete
          (unless (gethash "source" table)
            (error "Missing source"))
          (unless (or (gethash "commit" table) (gethash "version" table))
            (error "Missing commit or version"))
          (unless (gethash "systems" table)
            (error "Missing systems"))))
    (error (e)
      (format t "Error processing ~A: ~A~%" (getf repo :name) e))))

(defun print-table (stream hash-table)
  ;; Determine the maximum width for each column
  (let* ((keys (loop for k being the hash-keys of hash-table collect k))
         (values (loop for v being the hash-values of hash-table collect v))
         (max-key-length (reduce 'max keys :key 'length))
         (max-value-length (reduce 'max values :key 'length))
         (border (format nil "|~A+~A|"
                         (format nil "~v@{~A~:*~}" (+ max-key-length 2) "-")
                         (format nil "~v@{~A~:*~}" (+ max-value-length 2) "-"))))

    ;; Print the top border
    (format stream "~A~%" border)

    ;; Print each row
    (maphash (lambda (k v)
               (format stream "| ~vA | ~vA |~%"
                       max-key-length k
                       max-value-length v))
             hash-table)

    ;; Print the bottom border
    (format stream "~A~%" border)))

(defun file-exists-in-dir-or-subdir-p (filename dir)
  "Check if FILENAME exists in DIR or any of its subdirectories."
  (let ((dir-contents (uiop:directory-files dir)))
    (or (some (lambda (file)
                (string= filename (format nil "~A.~A" (pathname-name file) (pathname-type file))))
              dir-contents)
        (some #'(lambda (subdir)
                  (file-exists-in-dir-or-subdir-p filename subdir))
              (uiop:subdirectories dir)))))

(defun find-asd-files (dir)
  "Return a list of all .asd files in DIR and its subdirectories."
  (let ((result nil))
    (labels ((recur (d)
               (dolist (path (uiop:directory-files d))
                 (when (string= "asd" (pathname-type path))
                   (push (pathname-name path) result)))
               (dolist (subdir (uiop:subdirectories d))
                 (recur subdir))))
      (recur dir)
      result)))

(defun remove-test-strings (lst)
  "Remove strings containing 'test' from LST."
  (remove-if (lambda (str)
               (search "test" str))
             lst))

(defun format-space-separated (lst)
  "Format a list of strings into a single space-separated string."
  (reduce (lambda (a b) (concatenate 'string a " " b)) lst))

#|
(dolist (repo *repos*)
  (handler-case
      (let (project-name description table)
        (multiple-value-setq (project-name description table)
          (parse-readme.org (format nil "~A/README.org" (getf repo :name))))
        (when (uiop:directory-exists-p (format nil "repos/~A/" (getf repo :name)))
          (let ((systems (split-sequence:split-sequence #\Space (gethash "systems" table))))
            (dolist (system systems)
              (unless (file-exists-in-dir-or-subdir-p
                       (format nil "~A.asd" system)
                       (format nil "repos/~A/" (getf repo :name)))
                (setf (gethash "systems" table)
                      (remove-test-strings (find-asd-files (format nil "repos/~A/" (getf repo :name)))))
                (uiop:with-output-file (stream (format nil "~A/README.org" project-name) :if-exists :overwrite)
                  (format stream "* ~A~%~A" project-name description)
                  (print-table stream table))
                (legit:with-chdir (project-name)
                  (legit:git-add :paths "README.org")
                  (legit:git-commit :message "Update")
                  (legit:git-push)))))))
    (error (e)
      (format t "Error processing ~A: ~A~%" (getf repo :name) e))))

(dolist (repo *repos*)
  (handler-case
      (let (project-name description table)
        (multiple-value-setq (project-name description table)
          (parse-readme.org (format nil "~A/README.org" (getf repo :name))))
        (when (uiop:directory-exists-p (format nil "repos/~A/" (getf repo :name)))
          (when (char= (char (gethash "systems" table) 0) #\()
            (let ((systems (string-trim "()" (gethash "systems" table))))
              (setf (gethash "systems" table) systems)
              (uiop:with-output-file (stream (format nil "~A/README.org" project-name) :if-exists :overwrite)
                (format stream "* ~A~%~A" project-name description)
                (print-table stream table))
              (legit:with-chdir (project-name)
                (legit:git-add :paths "README.org")
                (legit:git-commit :message "Update")
                (legit:git-push))))))
    (error (e)
      (format t "Error processing ~A: ~A~%" (getf repo :name) e))))

            (dolist (system systems)
              (unless (file-exists-in-dir-or-subdir-p
                       (format nil "~A.asd" system)
                       (format nil "repos/~A/" (getf repo :name)))
                (setf (gethash "systems" table)
                      (remove-test-strings (find-asd-files (format nil "repos/~A/" (getf repo :name)))))
                (uiop:with-output-file (stream (format nil "~A/README.org" project-name) :if-exists :overwrite)
                  (format stream "* ~A~%~A" project-name description)
                  (print-table stream table))
                (legit:with-chdir (project-name)
                  (legit:git-add :paths "README.org")
                  (legit:git-commit :message "Update")
                  (legit:git-push)))))))
|#

;;;
;;; Update all git repos to latest commit
;;;
(dolist (repo *repos*)
  (handler-case
      (let (project-name description table)
        (multiple-value-setq (project-name description table)
          (parse-readme.org (format nil "~A/README.org" (getf repo :name))))

	(unless (gethash "deadlink" table)
          (let ((commit (gethash "commit" table)))
            (when commit
              (let ((repo-dir (format nil "repos/~A/" project-name))
                    head)
		(format t "Checking ~A~%" project-name)
		(when (not (uiop:directory-exists-p repo-dir))
                  (legit:with-chdir ("repos")
                    (let ((repo (subseq (gethash "source" table) 4)))
                      (format t "Cloning ~A~%" repo)
                      (legit:git-clone (subseq (gethash "source" table) 4)))))
		(when (uiop:directory-exists-p repo-dir)
                  (legit:with-chdir (repo-dir)
                    (legit:git-config :name "pull.rebase" :value "true")
                    (legit:pull ".")
                    (setf head (legit:current-commit "." :short t)))
                  (when (not (string= head commit))
                    (format t "Updating ~A: Expecting ~A but found ~A~%" project-name commit head)
                    (setf (gethash "commit" table) head)
                    (uiop:with-output-file (stream (format nil "~A/README.org" project-name) :if-exists :overwrite)
                      (format stream "* ~A~%~A" project-name description)
                      (print-table stream table))
                    (legit:with-chdir (project-name)
                      (legit:git-add :paths "README.org")
                      (legit:git-commit :message "Update")
                      (legit:git-push)))))))))
    (error (e)
           (format t "Error processing ~A: ~A~%" (getf repo :name) e))))

(sb-ext:quit)
