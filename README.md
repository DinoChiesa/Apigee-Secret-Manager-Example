# Secret Manager Example

This sample shows how you can configure an Apigee API Proxy to
retrieve and decode a secret from Google Secret Manager.

## Deploying Apigee Proxies with Service Accounts

Each API Proxy within Apigee X can optionally be deployed with the identity of  a specified service account. The API Proxy can then use the identity of that service account when requesting access to other Google Cloud services, like Secret Manager, BigQuery, Data Loss Protection, PubSub, or any other GCP API.

The key to making this happen is the GoogleAuthentication element that you can append to
an HTTPTargetConnection in a target endpoint or in a ServiceCallout or ExternalCallout.

The configuration for Secret Manager looks like this:
```xml
  <HTTPTargetConnection>

    <Authentication>
      <GoogleAccessToken>
        <Scopes>
          <Scope>https://www.googleapis.com/auth/cloud-platform</Scope>
        </Scopes>
      </GoogleAccessToken>
    </Authentication>

    <SSLInfo>
      <Enabled>true</Enabled>
      <Enforced>true</Enforced>
      <IgnoreValidationErrors>true</IgnoreValidationErrors>
    </SSLInfo>

    <Properties>
      <Property name='success.codes'>2xx</Property>
    </Properties>

    <URL>https://secretmanager.googleapis.com</URL>
  </HTTPTargetConnection>
```


## A Working Example

This repo contains an example that shows how this works.

The sample shows how you can create a secret and allow the API Proxy to access the secret.

To run this sample, you need the following pre-requisites:
- an Apigee X project
- a bash-compatible shell
- [apigeecli](https://github.com/apigee/apigeecli/blob/main/docs/apigeecli.md)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- [jq](https://jqlang.github.io/jq/)
- [curl](https://curl.se/)
- [openssl](https://www.openssl.org/)

The [Google Cloud Shell](https://cloud.google.com/shell) has all of these. You
can run this from there, if you like.


To deploy it, use the script:

```sh
export APIGEE_ENV=my-environment
export PROJECT=my-apigee-org
./setup-secret-manager-example.sh
```

The setup script sets up the following:
 - a Service account for this example
 - An example API proxy that runs with the identity of that service account
 - A secret, a simple string, in Google Cloud secret manager, in the same project.
 - A second secret, an RSA Private key, in Google Cloud secret manager, in the same project.


This will take a few moments. When it completes, you will see this kind of output:
```
  ...
Created version [1] of the secret [apigee-example-secret].

The secret value is:
  secret-20240607-111148-OmGDW1LPju

All the Apigee artifacts are successfully created.

To try:
  curl -i $apigee/example-secret-accessor-proxy/t1

You should see the value that was inserted, shown above.

or, to tell the proxy to retrieve your own secret:
  curl -i $apigee/example-secret-accessor-proxy/t2?secretid=my-secret\&secretversion=1

or, to tell the proxy to retrieve an RSA Key from SecretManager, and sign a JWT with that key:
   curl -i $apigee/example-secret-accessor-proxy/t3  -d ''

You should see a signed JWT in a response header.

```

After setting it up, you can demonstrate it.

The following examples assume `$apigee` is a variable that holds the endpoint at
which you can reach your API proxies. To set this, you might use something like
this:

```
apigee=https://35.207.223.215.nip.io
```

...replacing the `35.207.223.215` with the IP address of your Apigee instance,
which you can find in the Google Cloud console under Apigee / Management /
Instances .

After you set that, the following will retrieve version 1 of the secret with the hard-coded id of `apigee-example-secret`
```
 curl -i $apigee/example-secret-accessor-proxy/t1
```

Or, you can try to retrieve an arbitrary version of any secret, this way:
```
 curl -i $apigee/example-secret-accessor-proxy/t2?secretid=my-secret\&secretversion=2
```

Or, get a signed JWT:
```
 curl -i $apigee/example-secret-accessor-proxy/t3  -d ''
```

You should be able to decode that JWT with any tool. To verify it, you can use the public key PEM file that will be created in your directory. 

To have a closer look at what's happening, you can turn on a debug session, to
watch the execution of the proxy.


### Cleanup

To remove the configuration from this example in your Apigee Organization, run this command from your shell:

```bash
./clean-secret-manager-example.sh
```


## Disclaimer

This example is not an official Google product, nor is it part of an
official Google product.


## Support

This example is open-source software, and is not a supported part of Apigee.  If
you need assistance, you can try inquiring on [the Google Cloud Community forum
dedicated to Apigee](https://goo.gle/apigee-community) There is no service-level
guarantee for responses to inquiries posted to that site.

## License

This material is [Copyright 2024 Google LLC](./NOTICE).
and is licensed under the [Apache 2.0 License](LICENSE).
