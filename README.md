# sandboxes

# RUN tenv tofu install "${TOFU_VERSION}" \
#     && tenv tofu use "${TOFU_VERSION}" \
#     && ln -sf "${HOME}/.tenv/OpenTofu/${TOFU_VERSION}/tofu" "${HOME}/bin/tofu"

# # Print versions to verify installation
# RUN az version \
#   && tenv --version