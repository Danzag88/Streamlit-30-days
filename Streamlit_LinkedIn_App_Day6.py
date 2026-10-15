import streamlit as st
from snowflake.snowpark import Session
from snowflake.snowpark.context import get_active_session
from snowflake.snowpark.functions import ai_complete

st.title("LinkedIn Post Generator v2")


@st.cache_resource
def open_session():
    """Use the Snowsight login, or the secrets saved on Streamlit Cloud."""
    try:
        return get_active_session()
    except Exception:
        return Session.builder.configs(st.secrets["connections"]["snowflake"]).create()

content = st.text_input(
    "Content URL:",
    "https://docs.snowflake.com/en/user-guide/views-semantic/overview",
)
tone = st.selectbox("Tone:", ["Professional", "Casual", "Funny"])
word_count = st.slider("Approximate word count:", 50, 300, 100)

if st.button("Generate Post"):
    try:
        session = open_session()
        prompt = f"""
        You are an expert social media manager. Generate a LinkedIn post based on the following:

        Tone: {tone}
        Desired Length: Approximately {word_count} words
        Use content from this URL: {content}

        Generate only the LinkedIn post text. Use dash for bullet points.
        """

        with st.status("Starting engine...", expanded=True) as status:
            st.write("Thinking: Analyzing constraints and tone...")
            st.write("Generating: contacting Snowflake Cortex...")
            answer = session.range(1).select(
                ai_complete(model="claude-sonnet-4-6", prompt=prompt).alias("response")
            ).collect()[0][0]
            post = "" if answer is None else str(answer)
            st.write("Post generation completed!")
            status.update(
                label="Post Generated Successfully!",
                state="complete",
                expanded=False,
            )

        st.subheader("Generated Post:")
        st.markdown(post)
    except Exception as error:
        st.error("The post could not be generated.")
        st.exception(error)

st.divider()
st.caption("Day 6: Status UI for Long-Running Task | 30 Days of AI")
