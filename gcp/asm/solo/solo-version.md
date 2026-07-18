https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/


Both Solo’s standard and solo distributions of Istio come in the following optional varieties.

- FIPS: An image that is tagged with fips complies with NIST FIPS, for use cases that require federal information processing capabilities. For more information, see About Solo FIPS distribution of Istio. Examples: 1.30.2-fips, 1.30.2-solo-fips
- Distroless: An image that is tagged with distroless is a slimmed down distribution with the minimum set of binary dependencies to run the image, for enhanced performance and security. Note that if your app relies on package management, shell, or other operating system tools such as pip, apt, ls, grep, or bash, you must find another way to install these dependencies. Examples: 1.30.2-distroless, 1.30.2-solo-distroless
An image might be tagged to meet multiple use cases, such as 1.30.2-solo-fips-distroless.


https://docs.solo.io/istio/1.30.x/ambient/about/images/overview/


ns ==> created istio-system
